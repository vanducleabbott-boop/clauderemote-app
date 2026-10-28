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

    private func response(_ code: Int, html: Bool = true) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://claude.example.com/api/chats")!, statusCode: code, httpVersion: nil,
                        headerFields: ["Content-Type": html ? "text/html; charset=UTF-8" : "application/json"])!
    }

    // Trang loi HTML cua Cloudflare khi tunnel/PC chap chon khong duoc coi la bat dang nhap (v4.3)
    func testCloudflareErrorPageIsNotLogin() {
        let page = Data("<!DOCTYPE html><title>502 Bad gateway</title>".utf8)
        XCTAssertFalse(CloudflareAccess.isAccessResponse(response(502), data: page))
        XCTAssertFalse(CloudflareAccess.isAccessResponse(response(530), data: page))
        XCTAssertFalse(CloudflareAccess.isAccessResponse(response(200, html: false), data: Data("[]".utf8)))
    }

    func testAccessLoginPageIsLogin() {
        let page = Data("<html><body>Sign in</body></html>".utf8)
        XCTAssertTrue(CloudflareAccess.isAccessResponse(response(200), data: page))
        let redirected = HTTPURLResponse(url: URL(string: "https://team.cloudflareaccess.com/cdn-cgi/access/login")!,
                                         statusCode: 200, httpVersion: nil, headerFields: nil)!
        XCTAssertTrue(CloudflareAccess.isAccessResponse(redirected, data: nil))
    }
}
