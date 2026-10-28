import XCTest
@testable import ClaudeRemote

final class CloudflareAccessTests: XCTestCase {
    private func base64URL(_ string: String) -> String {
        Data(string.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func makeJWT(header: String = #"{"alg":"none"}"#, payload: String, signature: String = "sig") -> String {
        "\(base64URL(header)).\(base64URL(payload)).\(signature)"
    }

    func testJwtExpiryValidFakeToken() {
        let payload = #"{"exp":1893456000,"sub":"test"}"#
        let token = makeJWT(payload: payload)
        let expiry = CloudflareAccess.jwtExpiry(token)
        XCTAssertEqual(expiry, Date(timeIntervalSince1970: 1893456000))
    }

    func testJwtExpiryPayloadWithBase64URLChars() {
        // Chuỗi payload sau khi base64 tiêu chuẩn có chứa '+' và '/',
        // khi mã hóa base64url sẽ thành '-' và '_' và không có padding '='.
        let payload = #"{"exp":1893456000,"x":"???>>>~~~"}"#
        let token = makeJWT(payload: payload)
        let expiry = CloudflareAccess.jwtExpiry(token)
        XCTAssertEqual(expiry, Date(timeIntervalSince1970: 1893456000))
    }

    func testJwtExpiryGarbageStrings() {
        XCTAssertNil(CloudflareAccess.jwtExpiry("abc"))
        XCTAssertNil(CloudflareAccess.jwtExpiry("a.b.c"))
    }
}
