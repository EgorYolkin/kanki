import XCTest
@testable import Kanki

final class ServerConfigurationTests: XCTestCase {
    func testAcceptsHTTPAndHTTPs() throws {
        let http = try XCTUnwrap(ServerConfiguration(rawValue: " http://100.64.0.1:8000 "))
        let https = try XCTUnwrap(ServerConfiguration(rawValue: "https://kanki.example.com"))

        XCTAssertEqual(http.baseURL.absoluteString, "http://100.64.0.1:8000")
        XCTAssertEqual(https.baseURL.absoluteString, "https://kanki.example.com")
        XCTAssertEqual(http.displayValue, "http://100.64.0.1:8000")
    }

    func testStripsRootPath() throws {
        let configuration = try XCTUnwrap(ServerConfiguration(rawValue: "http://10.0.0.2:8000/"))

        XCTAssertEqual(configuration.baseURL.absoluteString, "http://10.0.0.2:8000")
    }

    func testRejectsInvalidValues() {
        let invalid = [
            "",
            "kanki.example.com",
            "ftp://kanki.example.com",
            "http://",
            "http://user:secret@10.0.0.2:8000",
            "http://10.0.0.2:8000/api",
            "http://10.0.0.2:8000?token=x",
            "http://10.0.0.2:8000#fragment"
        ]

        for value in invalid {
            XCTAssertNil(ServerConfiguration(rawValue: value), "Должен отклонить \(value)")
        }
    }
}
