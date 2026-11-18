import CryptoKit
import Foundation
import Security

enum DeltaTransport {
    enum PinError: Error {
        case invalidPin
    }

    /// Создаёт сессию без редиректов и кэша. Пустой пин оставляет системную проверку TLS.
    static func session(pin: String) throws -> URLSession {
        makeSession(delegate: DeltaTransportDelegate(pin: try decodePin(pin)))
    }

    #if KANKI_E4_TLS_FIXTURE
    /// Только для отдельной сборки Э4: собственный CA для этой проверки, без изменений хранилища системы.
    static func session(pin: String, testAnchorDER: Data) throws -> URLSession {
        makeSession(delegate: DeltaTransportDelegate(pin: try decodePin(pin), testAnchorDER: testAnchorDER))
    }
    #endif

    private static func decodePin(_ pin: String) throws -> Data? {
        guard !pin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let bytes = Data(base64Encoded: pin), bytes.count == SHA256Digest.byteCount,
              bytes.base64EncodedString() == pin else {
            throw PinError.invalidPin
        }

        return bytes
    }

    private static func makeSession(delegate: DeltaTransportDelegate) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
}

private final class DeltaTransportDelegate: NSObject, URLSessionTaskDelegate {
    private let pin: Data?
    #if KANKI_E4_TLS_FIXTURE
    private let testAnchorDER: Data?
    #endif

    init(pin: Data?) {
        self.pin = pin
        #if KANKI_E4_TLS_FIXTURE
        testAnchorDER = nil
        #endif
    }

    #if KANKI_E4_TLS_FIXTURE
    init(pin: Data?, testAnchorDER: Data) {
        self.pin = pin
        self.testAnchorDER = testAnchorDER
    }
    #endif

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust, let pin else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let trust = space.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        #if KANKI_E4_TLS_FIXTURE
        if let testAnchorDER {
            guard let anchor = SecCertificateCreateWithData(nil, testAnchorDER as CFData),
                  SecTrustSetAnchorCertificates(trust, [anchor] as CFArray) == errSecSuccess else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }
        #endif

        // Политика из URLSession уже включает проверку имени хоста. Не заменяем её.
        guard SecTrustEvaluateWithError(trust, nil),
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let hash = P256SubjectPublicKeyInfo.hash(of: leaf),
              hash == pin else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum P256SubjectPublicKeyInfo {
    // DER AlgorithmIdentifier: id-ecPublicKey и именованная кривая prime256v1 (P-256).
    private static let algorithmIdentifier: [UInt8] = [
        0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01,
        0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07
    ]

    static func hash(of leaf: SecCertificate) -> SHA256Digest? {
        let der = SecCertificateCopyData(leaf) as Data
        return der.withUnsafeBytes { bytes in
            var reader = DERReader(bytes)
            guard let certificate = reader.read(0x30) else { return nil }

            reader = DERReader(UnsafeRawBufferPointer(rebasing: bytes[certificate]))
            guard let tbs = reader.read(0x30) else { return nil }

            let tbsBytes = UnsafeRawBufferPointer(rebasing: reader.bytes[tbs])
            reader = DERReader(tbsBytes)
            // TBSCertificate: необязательная version, затем поля перед subjectPublicKeyInfo.
            if reader.nextTag == 0xa0, reader.read(0xa0) == nil { return nil }
            guard reader.read(0x02) != nil,  // serialNumber
                  reader.read(0x30) != nil,  // signature
                  reader.read(0x30) != nil,  // issuer
                  reader.read(0x30) != nil,  // validity
                  reader.read(0x30) != nil else { return nil }  // subject

            let start = reader.offset
            guard let spki = reader.read(0x30), tbsBytes[spki].starts(with: algorithmIdentifier) else { return nil }

            var hash = SHA256()
            hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: tbsBytes[start..<reader.offset]))
            return hash.finalize()
        }
    }

    /// Читает диапазоны содержимого TLV в пределах родительского DER-буфера.
    private struct DERReader {
        let bytes: UnsafeRawBufferPointer
        private(set) var offset = 0

        var nextTag: UInt8? {
            offset < bytes.count ? bytes[offset] : nil
        }

        init(_ bytes: UnsafeRawBufferPointer) {
            self.bytes = bytes
        }

        mutating func read(_ tag: UInt8) -> Range<Int>? {
            guard nextTag == tag, bytes.count - offset >= 2 else { return nil }

            let firstLength = Int(bytes[offset + 1])
            offset += 2
            var length = firstLength
            if firstLength >= 0x80 {
                let count = firstLength & 0x7f
                guard count > 0, count < MemoryLayout<Int>.size,
                      count <= bytes.count - offset, bytes[offset] != 0 else { return nil }

                length = 0
                for _ in 0..<count {
                    length = length << 8 | Int(bytes[offset])
                    offset += 1
                }
                guard length >= 0x80 else { return nil }
            }
            guard length <= bytes.count - offset else { return nil }

            let start = offset
            offset += length
            return start..<offset
        }
    }
}
