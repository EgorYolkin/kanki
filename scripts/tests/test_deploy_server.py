"""Exercise credential handling against a real loopback HTTP endpoint."""

import contextlib
import http.server
import io
import json
import threading
import unittest
from unittest import mock

from scripts import deploy_server as deploy


class DeviceTokenTests(unittest.TestCase):
    def setUp(self):
        self.secret = "synthetic-admin-credential"
        self.requests = []
        self.status = 200
        test = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                test.requests.append((self.path, self.headers["Authorization"], json.loads(body)))
                self.send_response(test.status)
                self.end_headers()
                self.wfile.write(b'{"token":"device-only-token"}')

            def log_message(self, format, *args):
                pass

        self.server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        self.server.timeout = 3
        self.addCleanup(self.server.server_close)

    def issue(self):
        def local_transport(target, command, *, input_text=None, dry_run):
            self.assertNotIn(self.secret, command)
            return deploy.run(["bash", "-c", command], input_text=input_text, dry_run=dry_run)

        worker = threading.Thread(target=self.server.handle_request, daemon=True)
        worker.start()
        self.addCleanup(worker.join, 5)
        with mock.patch.object(deploy, "ssh", side_effect=local_transport):
            return deploy.issue_device_token(
                "unused@loopback", self.server.server_port, "phone's label", self.secret
            )

    def test_credential_reaches_http_server_but_not_command_logs(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            token = self.issue()
        self.assertEqual(token, "device-only-token")
        self.assertEqual(self.requests, [
            ("/v1/tokens", f"Bearer {self.secret}", {"label": "phone's label"})
        ])
        self.assertNotIn(self.secret, output.getvalue())

    def test_failed_request_does_not_expose_credential(self):
        self.status = 401
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            with self.assertRaises(SystemExit):
                self.issue()
        self.assertEqual(self.requests[0][1], f"Bearer {self.secret}")
        self.assertNotIn(self.secret, output.getvalue())


if __name__ == "__main__":
    unittest.main()
