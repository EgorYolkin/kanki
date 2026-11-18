#!/bin/bash
# Run on macOS 14 or later: bash experiments/e4_tls.sh
# Requires Xcode with Swift 6, OpenSSL/LibreSSL and Python 3.7+ (no packages).
# E4 uses only synthetic TLS fixtures on loopback; no Anki backend or .apkg.
# All certificates, keys, binaries and logs are temporary. No trust-store edits.
set -euo pipefail
umask 077

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/kanki-e4.XXXXXXXX")
server_pid=''

cleanup() {
  local status=$?
  if [[ -n $server_pid ]] && kill "$server_pid" 2>/dev/null; then
    wait "$server_pid" 2>/dev/null || :
  fi
  if ((status != 0)) && [[ -s $work/server.log ]]; then
    cat "$work/server.log" >&2
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

cat > "$work/root.cnf" <<'CNF'
[req]
distinguished_name = dn
[dn]
[ca]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
CNF

# Make a temporary P-256 CA; also export its DER for scoped trust evaluation.
make_ca() {
  local name=$1
  openssl ecparam -name prime256v1 -genkey -noout -out "$work/$name.key"
  openssl req -new -x509 -sha256 -days 2 -key "$work/$name.key" \
    -config "$work/root.cnf" -extensions ca -subj "/CN=Kanki E4 $name" \
    -out "$work/$name.pem"
  openssl x509 -in "$work/$name.pem" -outform DER -out "$work/$name.der"
}

# Sign a leaf from the named CSR, using the specified CA, serial and SAN.
sign_leaf() {
  local name=$1 key=$2 issuer=$3 serial=$4 san=$5
  cat > "$work/leaf.ext" <<EOF
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = $san
authorityKeyIdentifier = keyid,issuer
EOF
  openssl x509 -req -sha256 -days 1 -in "$work/$key.csr" \
    -CA "$work/$issuer.pem" -CAkey "$work/$issuer.key" -set_serial "$serial" \
    -extfile "$work/leaf.ext" -out "$work/$name.pem"
}

# Compute the expected pin independently of the Swift implementation.
spki_pin() {
  openssl x509 -in "$work/$1.pem" -pubkey -noout \
    | openssl pkey -pubin -pubout -outform DER \
    | openssl dgst -sha256 -binary \
    | openssl base64 -A
}

make_ca trusted
make_ca unknown
for key in main rotated; do
  openssl ecparam -name prime256v1 -genkey -noout -out "$work/$key.key"
  openssl req -new -key "$work/$key.key" -subj '/CN=Kanki E4 leaf' \
    -out "$work/$key.csr"
done
sign_leaf original main trusted 10 IP:127.0.0.1
sign_leaf renewed main trusted 11 IP:127.0.0.1
sign_leaf rotated rotated trusted 12 IP:127.0.0.1
sign_leaf untrusted main unknown 13 IP:127.0.0.1
sign_leaf wrong_host main trusted 14 DNS:wrong.invalid
pin=$(spki_pin original)
rotated_pin=$(spki_pin rotated)

cat > "$work/Runner.swift" <<'SWIFT'
import Foundation

private struct Failure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

@main
private enum E4 {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("E4 failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func run() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 9 else { throw Failure("invalid fixture arguments") }
        let work = URL(fileURLWithPath: arguments[1], isDirectory: true)
        let pin = arguments[2]
        let rotatedPin = arguments[3]
        let original = arguments[4]
        let renewed = arguments[5]
        let rotated = arguments[6]
        let untrusted = arguments[7]
        let wrongHost = arguments[8]
        let trusted = try Data(contentsOf: work.appendingPathComponent("trusted.der"))
        let unknown = try Data(contentsOf: work.appendingPathComponent("unknown.der"))

        try await expect(200, "original certificate", pin: pin, anchor: trusted, port: original)
        try await expect(200, "same key after renewal", pin: pin, anchor: trusted, port: renewed)
        try await expect(200, "other key with its own pin", pin: rotatedPin, anchor: trusted, port: rotated)
        try await expectRejection("trusted other key", pin: pin, anchor: trusted, port: rotated)
        try await expect(200, "same key with its other CA trusted", pin: pin, anchor: unknown, port: untrusted)
        try await expectRejection("matching key without trusted chain", pin: pin, anchor: trusted, port: untrusted)
        try await expectRejection("matching key with wrong hostname", pin: pin, anchor: trusted, port: wrongHost)
        try await expectRejection("fixture CA absent from system trust", pin: pin, port: original)
        try await expectRejection("blank pin keeps system trust", pin: " \n\t", port: original)
        try await expect(307, "redirect not followed", pin: pin, anchor: trusted, port: original, path: "/redirect")

        for bad in ["\(pin)\n", "sha256/\(pin)", "AA==", String(pin.dropLast())] {
            do {
                let session = try DeltaTransport.session(pin: bad)
                session.invalidateAndCancel()
                throw Failure("invalid pin accepted: \(bad.debugDescription)")
            } catch DeltaTransport.PinError.invalidPin {
                continue
            }
        }
        print("PASS: malformed pins rejected")
    }

    private static func fetch(pin: String, anchor: Data?, port: String, path: String) async throws -> Int {
        guard let url = URL(string: "https://127.0.0.1:\(port)\(path)") else {
            throw Failure("invalid loopback URL")
        }
        let session: URLSession
        if let anchor {
            session = try DeltaTransport.session(pin: pin, testAnchorDER: anchor)
        } else {
            session = try DeltaTransport.session(pin: pin)
        }
        defer { session.finishTasksAndInvalidate() }
        let request = URLRequest(url: url, timeoutInterval: 5)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure("not an HTTP response") }

        return http.statusCode
    }

    private static func expect(
        _ status: Int,
        _ label: String,
        pin: String,
        anchor: Data,
        port: String,
        path: String = "/reviews"
    ) async throws {
        let observed = try await fetch(pin: pin, anchor: anchor, port: port, path: path)
        guard observed == status else { throw Failure("\(label): expected HTTP \(status), got \(observed)") }

        print("PASS: \(label) (HTTP \(status))")
    }

    private static func expectRejection(
        _ label: String,
        pin: String,
        anchor: Data? = nil,
        port: String
    ) async throws {
        do {
            let status = try await fetch(pin: pin, anchor: anchor, port: port, path: "/reviews")
            throw Failure("\(label): unexpectedly got HTTP \(status)")
        } catch let error as URLError {
            switch error.code {
            case .cancelled, .userCancelledAuthentication, .serverCertificateUntrusted,
                 .serverCertificateHasUnknownRoot, .secureConnectionFailed:
                print("PASS: \(label) (URLSession error \(error.code.rawValue))")
            default:
                throw Failure("\(label): unexpected URLSession error \(error)")
            }
        }
    }
}
SWIFT

# Allow scoped custom trust evaluation for the runner's loopback IP only.
# The runner still uses HTTPS and the transport still checks chain + hostname.
cat > "$work/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>app.kanki.e4-tls</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSExceptionDomains</key>
    <dict>
      <key>127.0.0.1</key>
      <dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key>
        <true/>
      </dict>
    </dict>
  </dict>
</dict>
</plist>
PLIST

xcrun --sdk macosx swiftc -swift-version 6 -D KANKI_E4_TLS_FIXTURE \
  "$repo_dir/Kanki/Server/DeltaTransport.swift" "$work/Runner.swift" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist \
  -Xlinker "$work/Info.plist" \
  -o "$work/e4"

python3 - "$work" > "$work/server.log" 2>&1 <<'PY' &
import http.server
import pathlib
import ssl
import sys
import threading


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        if self.path == "/redirect":
            self.send_response(307)
            self.send_header("Location", "/reviews")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        body = b"synthetic delta response\n"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def serve(work: pathlib.Path) -> None:
    """
    Start one TLS listener per certificate and publish their ports atomically.
    """

    fixtures = (
        ("original", "main"),
        ("renewed", "main"),
        ("rotated", "rotated"),
        ("untrusted", "main"),
        ("wrong_host", "main"),
    )
    ports = []
    for cert, key in fixtures:
        server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(work / f"{cert}.pem", work / f"{key}.key")
        server.socket = context.wrap_socket(server.socket, server_side=True)
        ports.append(str(server.server_port))
        threading.Thread(target=server.serve_forever, daemon=True).start()

    ready = work / "ports.tmp"
    ready.write_text(" ".join(ports) + "\n", encoding="ascii")
    ready.rename(work / "ports")
    threading.Event().wait()


serve(pathlib.Path(sys.argv[1]))
PY
server_pid=$!

for ((attempt = 0; attempt < 50; attempt++)); do
  if [[ -f $work/ports ]] || ! kill -0 "$server_pid" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if [[ ! -f $work/ports ]]; then
  printf '%s\n' 'E4: loopback listeners did not start' >&2
  exit 1
fi
read -r -a ports < "$work/ports"
"$work/e4" "$work" "$pin" "$rotated_pin" "${ports[@]}"
