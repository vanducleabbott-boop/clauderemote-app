//
//  CloudflareAccess.swift
//  ClaudeRemote
//
//  Helper xac thuc Cloudflare Access tren iOS.
//

import Foundation
import SwiftUI
import UserNotifications
import WebKit

public final class CloudflareAccess: ObservableObject {
    public static let shared = CloudflareAccess()
    public static let didLoginNotification = Notification.Name("CloudflareAccessDidLogin")

    private static let cookieKey = "cf_authorization"
    private static let expKey = "cf_authorization_exp"
    private static let notificationIdentifier = "cloudflare-access-expiry-clauderemote"

    @Published public var showLogin: Bool = false
    @Published public var loginURL: URL?

    private init() {}

    /// Cookie CF_Authorization lay tu Keychain.
    public static var cookie: String? {
        Keychain.get(cookieKey)
    }

    /// Thoi diem het han cua phien Cloudflare Access lay tu Keychain.
    public static var expiryDate: Date? {
        guard let str = Keychain.get(expKey), let seconds = TimeInterval(str) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Canh bao phien Cloudflare sap het han (trong vong 2 ngay tro xuong hoac da qua han).
    public static var daysLeftWarning: Bool {
        guard let exp = expiryDate else { return false }
        return exp.timeIntervalSinceNow <= 2 * 86400
    }

    /// Trich xuat thoi diem het han (exp) tu chuoi JWT.
    /// Tra ve nil neu sai dinh dang. KHONG in hay log gia tri cookie/token.
    public static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }

        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        if let exp = json["exp"] as? NSNumber {
            return Date(timeIntervalSince1970: exp.doubleValue)
        } else if let exp = json["exp"] as? Double {
            return Date(timeIntervalSince1970: exp)
        } else if let exp = json["exp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(exp))
        }
        return nil
    }

    /// Luu cookie CF_Authorization vao Keychain va cap nhat thoi gian het han + dat thong bao.
    public static func save(_ value: String) {
        Keychain.set(value, for: cookieKey)
        if let exp = jwtExpiry(value) {
            Keychain.set(String(Int(exp.timeIntervalSince1970)), for: expKey)
        } else {
            Keychain.delete(expKey)
        }
        scheduleExpiryNotification()
    }

    /// Xoa cookie khoi Keychain, HTTPCookieStorage va WKWebsiteDataStore, huy thong bao het han.
    public static func clear() {
        Keychain.delete(cookieKey)
        Keychain.delete(expKey)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies where cookie.name == "CF_Authorization" {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        DispatchQueue.main.async {
            let store = WKWebsiteDataStore.default().httpCookieStore
            store.getAllCookies { cookies in
                for cookie in cookies where cookie.name == "CF_Authorization" {
                    store.delete(cookie, completionHandler: nil)
                }
            }
        }
    }

    /// Dat thong bao nhac nho truoc khi phien Cloudflare het han 2 ngay (hoac sau 60 giay neu da can/qua moc do).
    public static func scheduleExpiryNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        guard let exp = expiryDate else { return }

        center.getNotificationSettings { settings in
            let schedule = {
                let twoDaysBefore = exp.timeIntervalSinceNow - (2 * 86400)
                let interval: TimeInterval = twoDaysBefore > 0 ? twoDaysBefore : 60

                let content = UNMutableNotificationContent()
                content.title = "Cloudflare sắp hết hạn"
                content.body = "Phiên Cloudflare của ClaudeRemote hết hạn \(formatExpiry(exp)). Mở app → Cài đặt → Đăng nhập lại Cloudflare."
                content.sound = .default

                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
                center.add(request, withCompletionHandler: nil)
            }

            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        schedule()
                    }
                }
            } else if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
                schedule()
            }
        }
    }

    /// Dinh dang ngay het han thanh chuoi "dd/MM/yyyy HH:mm" voi locale vi_VN de dung lai o UI.
    public static func formatExpiry(_ d: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy HH:mm"
        formatter.locale = Locale(identifier: "vi_VN")
        return formatter.string(from: d)
    }

    /// Gan cookie CF_Authorization vao request neu co.
    public static func apply(to request: inout URLRequest) {
        guard let value = cookie, !value.isEmpty else { return }
        request.setValue("CF_Authorization=\(value)", forHTTPHeaderField: "Cookie")
        request.httpShouldHandleCookies = false
    }

    /// Kiem tra URL co tro toi Cloudflare Access khong (host chua "cloudflareaccess.com").
    public static func isAccessURL(_ url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host.contains("cloudflareaccess.com")
    }

    /// Kiem tra response co phai la yeu cau xac thuc / redirect tu Cloudflare Access khong.
    /// LUU Y: Ham nay chi dung o nhung endpoint ky vong ket qua la JSON (vi se coi Content-Type text/html bat dau bang "<" la trang login Access).
    public static func isAccessResponse(_ response: URLResponse?, data: Data?) -> Bool {
        guard let response = response else { return false }

        // 1. response.url la AccessURL
        if isAccessURL(response.url) {
            return true
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }

        // 2. HTTPURLResponse co statusCode 302/401/403 va header Location tro sang cloudflareaccess.com
        if [302, 401, 403].contains(httpResponse.statusCode) {
            if let location = httpResponse.value(forHTTPHeaderField: "Location")?.lowercased(),
               location.contains("cloudflareaccess.com") {
                return true
            }
        }

        // 3. Content-Type chua "text/html" va data bat dau (sau khi bo khoang trang) bang "<" ma khong phai JSON
        let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("text/html"), let data = data, !data.isEmpty {
            if let prefixString = String(data: data.prefix(1024), encoding: .utf8) {
                let trimmed = prefixString.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("<") {
                    return true
                }
            }
        }

        return false
    }

    /// Yeu cau hien thi man hinh dang nhap Cloudflare Access tren MainActor.
    @MainActor
    public func requestLogin(baseURL: URL) {
        self.loginURL = baseURL
        self.showLogin = true
    }

    /// Nap cookie CF_Authorization tu Keychain vao WKHTTPCookieStore va HTTPCookieStorage.
    public static func preloadWebCookies(for baseURL: URL) async {
        guard let value = cookie, !value.isEmpty, let host = baseURL.host else { return }

        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "CF_Authorization",
            .value: value,
            .domain: host,
            .path: "/",
            .secure: "TRUE"
        ]
        properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"

        guard let httpCookie = HTTPCookie(properties: properties) else { return }

        HTTPCookieStorage.shared.setCookie(httpCookie)

        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                WKWebsiteDataStore.default().httpCookieStore.setCookie(httpCookie) {
                    continuation.resume()
                }
            }
        }
    }

    /// So khop domain cua cookie voi host cua app (ho tro co dau cham dau va subdomain).
    public static func domainMatches(cookieDomain: String, host: String) -> Bool {
        let cleanCookie = cookieDomain.hasPrefix(".") ? String(cookieDomain.dropFirst()).lowercased() : cookieDomain.lowercased()
        let cleanHost = host.hasPrefix(".") ? String(host.dropFirst()).lowercased() : host.lowercased()

        if cleanCookie == cleanHost {
            return true
        }
        if cleanHost.hasSuffix("." + cleanCookie) {
            return true
        }
        return false
    }
}

public struct CloudflareLoginSheet: View {
    @ObservedObject private var access = CloudflareAccess.shared
    @Environment(\.dismiss) private var dismiss

    public let baseURL: URL
    public var onSuccess: (() -> Void)?

    public init(baseURL: URL? = nil, onSuccess: (() -> Void)? = nil) {
        self.baseURL = baseURL ?? CloudflareAccess.shared.loginURL ?? URL(string: "https://localhost")!
        self.onSuccess = onSuccess
    }

    public var body: some View {
        NavigationStack {
            CloudflareWebView(baseURL: baseURL, onSuccess: onSuccess)
                .navigationTitle("Cloudflare Access")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") {
                            access.showLogin = false
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct CloudflareWebView: UIViewRepresentable {
    let baseURL: URL
    let onSuccess: (() -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: baseURL)
        CloudflareAccess.apply(to: &request)
        webView.load(request)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL, onSuccess: onSuccess)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let baseURL: URL
        let onSuccess: (() -> Void)?
        private var didCaptureCookie: Bool = false

        init(baseURL: URL, onSuccess: (() -> Void)?) {
            self.baseURL = baseURL
            self.onSuccess = onSuccess
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkCookies(in: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            checkCookies(in: webView)
            decisionHandler(.allow)
        }

        private func checkCookies(in webView: WKWebView) {
            guard !didCaptureCookie else { return }
            guard let currentHost = webView.url?.host?.lowercased(),
                  let expectedHost = baseURL.host?.lowercased() else {
                return
            }

            // Neu URL van la cloudflareaccess.com thi cu de user nhap email + OTP
            if currentHost.contains("cloudflareaccess.com") {
                return
            }

            // Da ve dung host app (da qua /cdn-cgi/access/authorized)
            guard currentHost == expectedHost else {
                return
            }

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.didCaptureCookie else { return }

                if let authCookie = cookies.first(where: { cookie in
                    cookie.name == "CF_Authorization" && CloudflareAccess.domainMatches(cookieDomain: cookie.domain, host: expectedHost)
                }) {
                    self.didCaptureCookie = true
                    let cookieValue = authCookie.value
                    CloudflareAccess.save(cookieValue)

                    Task { @MainActor in
                        await CloudflareAccess.preloadWebCookies(for: self.baseURL)
                        NotificationCenter.default.post(name: CloudflareAccess.didLoginNotification, object: nil)
                        self.onSuccess?()
                        CloudflareAccess.shared.showLogin = false
                    }
                }
            }
        }
    }
}
