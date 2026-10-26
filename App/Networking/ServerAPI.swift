//
//  ServerAPI.swift
//  ClaudeRemote
//
//  Ket noi server Claude Remote (README server, muc "Giao dien chat"):
//  - HTTP: header "Authorization: Bearer <token>"
//  - WebSocket: query "?token=<token>"
//  baseURL chuan hoa: tu them "https://" neu thieu scheme, cat dau "/" cuoi.
//

import Foundation

// MARK: - Errors

public enum APIError: LocalizedError, Equatable {
    case missingConfiguration
    case invalidURL
    case unauthorized
    case httpError(statusCode: Int, message: String?)
    case networkError(String)
    case invalidResponse
    case decodingError(String)

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Chưa cài đặt URL hoặc Token máy chủ."
        case .invalidURL:
            return "Địa chỉ máy chủ (URL) không hợp lệ."
        case .unauthorized:
            return "Mã token không hợp lệ hoặc đã hết hạn (401 Unauthorized)."
        case .httpError(let code, let message):
            if code == 409 { return "Đang chạy, đợi xong lượt này rồi gửi tiếp." }
            if code == 404, message?.contains("not found") == true {
                return "Server chưa có giao diện chat. Trên PC chạy git pull rồi khởi động lại server."
            }
            if let msg = Self.serverMessage(message), !msg.isEmpty {
                return "Lỗi máy chủ (HTTP \(code)): \(msg)"
            }
            return "Lỗi máy chủ (HTTP \(code))."
        case .networkError(let details):
            return "Lỗi kết nối mạng: \(details)"
        case .invalidResponse:
            return "Máy chủ phản hồi không hợp lệ."
        case .decodingError(let details):
            return "Dữ liệu trả về không đúng định dạng: \(details)"
        }
    }

    /// Lay truong "error" trong JSON loi cua server
    private static func serverMessage(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = obj["error"] as? String {
            return err
        }
        return raw
    }
}

// MARK: - ServerAPI

public final class ServerAPI {
    public let baseURL: String
    public let token: String
    private let urlSession: URLSession

    public init(baseURL: String, token: String) {
        self.baseURL = Self.normalizeBaseURL(baseURL)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 60.0
        self.urlSession = URLSession(configuration: config)
    }

    /// Chuan hoa baseURL: cat khoang trang, them "https://" neu thieu scheme, bo dau "/" cuoi.
    public static func normalizeBaseURL(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") {
            s.removeLast()
        }
        if !s.isEmpty && !s.contains("://") {
            s = "https://" + s
        }
        return s
    }

    /// ws(s)://<host>/<path>?token=...&<query>
    public func webSocketURL(path: String, query: [URLQueryItem] = []) -> URL? {
        guard !baseURL.isEmpty, var components = URLComponents(string: baseURL) else {
            return nil
        }
        components.scheme = components.scheme?.lowercased() == "https" ? "wss" : "ws"
        var basePath = components.path
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        components.path = basePath + path
        components.queryItems = query + [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    // MARK: - Helpers

    static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#/"))

    static func encodeQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
    }

    func makeRequest(path: String, method: String, body: Data? = nil) throws -> URLRequest {
        guard !baseURL.isEmpty, !token.isEmpty else {
            throw APIError.missingConfiguration
        }
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 15.0
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
    }

    func perform(request: URLRequest, session: URLSession? = nil) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await (session ?? urlSession).data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
        return (data, try Self.check(response, data: data))
    }

    static func check(_ response: URLResponse, data: Data?) throws -> HTTPURLResponse {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        if http.statusCode == 401 {
            throw APIError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, message: data.flatMap { String(data: $0, encoding: .utf8) })
        }
        return http
    }

    func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }
}
