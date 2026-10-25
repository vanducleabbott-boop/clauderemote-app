//
//  ServerAPI.swift
//  ClaudeRemote
//
//  GIAO THUC SERVER CLAUDE REMOTE (Server Protocol Reference):
//  ============================================================
//  1. Authentication:
//     - HTTP Requests: Header "Authorization: Bearer <token>"
//     - WebSocket: Query parameter "?token=<token>" (percent-encoded)
//
//  2. HTTP Endpoints:
//     - GET    /api/sessions
//              Response: [Session]
//              Lay danh sach tat ca cac phien dang co tren server.
//     - POST   /api/sessions
//              Body JSON: NewSessionRequest { cwd, name, mode, tool, openTab }
//              Response: Session
//              Tao phien lam viec moi.
//     - DELETE /api/sessions/:id
//              Response: 200/204 OK
//              Xoa / huy phien lam viec theo ID.
//
//  3. WebSocket Endpoint:
//     - ws(s)://<host>:<port>/ws/:id?token=<token>
//       Truyen nhan du lieu terminal hai chieu giua app va server:
//       - Client -> Server:
//         + Binary (.data): du lieu ban phim tho (raw keystrokes, ANSI escape codes)
//         + Text (.string): lenh dieu khien JSON, vi du:
//           {"type":"resize","cols":80,"rows":24}
//       - Server -> Client:
//         + Binary (.data) hoac Text (.string): du lieu terminal output
//
//  4. Cau hinh chung:
//     - HTTP request timeout: 10 giay
//     - baseURL chuan hoa: tu dong them "https://" neu thieu scheme, cat dau "/" o cuoi.
//

import Foundation

// MARK: - Models

public struct Session: Codable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let cwd: String
    public let mode: String
    public let tool: String
    public let status: String
    public let createdAt: String?
    public let clients: Int?

    public var isRunning: Bool {
        status == "running"
    }

    enum CodingKeys: String, CodingKey {
        case id, name, cwd, mode, tool, status, createdAt, clients
    }

    public init(
        id: String,
        name: String,
        cwd: String,
        mode: String,
        tool: String,
        status: String,
        createdAt: String? = nil,
        clients: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.cwd = cwd
        self.mode = mode
        self.tool = tool
        self.status = status
        self.createdAt = createdAt
        self.clients = clients
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        cwd = try container.decode(String.self, forKey: .cwd)
        mode = try container.decode(String.self, forKey: .mode)
        tool = try container.decode(String.self, forKey: .tool)
        status = try container.decode(String.self, forKey: .status)
        clients = try container.decodeIfPresent(Int.self, forKey: .clients)

        // Decode linh hoat cho createdAt: co the la String, Int hoac Double
        if let stringVal = try? container.decodeIfPresent(String.self, forKey: .createdAt) {
            createdAt = stringVal
        } else if let intVal = try? container.decodeIfPresent(Int64.self, forKey: .createdAt) {
            createdAt = String(intVal)
        } else if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: .createdAt) {
            createdAt = String(format: "%.0f", doubleVal)
        } else {
            createdAt = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(cwd, forKey: .cwd)
        try container.encode(mode, forKey: .mode)
        try container.encode(tool, forKey: .tool)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(clients, forKey: .clients)
    }
}

public struct NewSessionRequest: Codable, Equatable {
    public let cwd: String
    public let name: String
    public let mode: String    // "normal" | "skip"
    public let tool: String    // "claude" | "agy"
    public let openTab: Bool

    public init(
        cwd: String,
        name: String,
        mode: String = "normal",
        tool: String = "claude",
        openTab: Bool = true
    ) {
        self.cwd = cwd
        self.name = name
        self.mode = mode
        self.tool = tool
        self.openTab = openTab
    }
}

// MARK: - Errors

public enum APIError: LocalizedError, Equatable {
    case missingConfiguration
    case invalidURL
    case unauthorized
    case httpError(statusCode: Int, message: String?)
    case networkError(String)
    case invalidResponse
    case decodingError(String)
    case encodingError(String)

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Chưa cài đặt URL hoặc Token máy chủ."
        case .invalidURL:
            return "Địa chỉ máy chủ (URL) không hợp lệ."
        case .unauthorized:
            return "Mã token không hợp lệ hoặc đã hết hạn (401 Unauthorized)."
        case .httpError(let code, let message):
            if let msg = message?.trimmingCharacters(in: .whitespacesAndNewlines), !msg.isEmpty {
                return "Lỗi máy chủ (HTTP \(code)): \(msg)"
            }
            return "Lỗi máy chủ (HTTP \(code))."
        case .networkError(let details):
            return "Lỗi kết nối mạng: \(details)"
        case .invalidResponse:
            return "Máy chủ phản hồi không hợp lệ."
        case .decodingError(let details):
            return "Dữ liệu trả về không đúng định dạng: \(details)"
        case .encodingError(let details):
            return "Không thể đóng gói dữ liệu gửi đi: \(details)"
        }
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
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 10.0
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
        while s.hasSuffix("/") {
            s.removeLast()
        }
        return s
    }

    /// Tra ve URL WebSocket cho phien voi query token da duoc percent-encode.
    public func webSocketURL(sessionId: String) -> URL? {
        guard !baseURL.isEmpty, var components = URLComponents(string: baseURL) else {
            return nil
        }

        // Chuyen scheme http -> ws, https -> wss
        if components.scheme?.lowercased() == "https" {
            components.scheme = "wss"
        } else {
            components.scheme = "ws"
        }

        var basePath = components.path
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }

        let encodedId = sessionId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionId
        components.path = "\(basePath)/ws/\(encodedId)"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url
    }

    /// Tao ban tin JSON text bao thay doi kich thuoc terminal: {"type":"resize","cols":N,"rows":M}
    public static func resizeMessage(cols: Int, rows: Int) -> String {
        "{\"type\":\"resize\",\"cols\":\(cols),\"rows\":\(rows)}"
    }

    // MARK: - API Calls

    /// GET /api/sessions
    public func listSessions() async throws -> [Session] {
        let request = try makeRequest(path: "/api/sessions", method: "GET")
        let (data, _) = try await perform(request: request)
        do {
            return try JSONDecoder().decode([Session].self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// POST /api/sessions
    public func createSession(_ r: NewSessionRequest) async throws -> Session {
        let body: Data
        do {
            body = try JSONEncoder().encode(r)
        } catch {
            throw APIError.encodingError(error.localizedDescription)
        }

        let request = try makeRequest(path: "/api/sessions", method: "POST", body: body)
        let (data, _) = try await perform(request: request)
        do {
            return try JSONDecoder().decode(Session.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// DELETE /api/sessions/:id
    public func deleteSession(id: String) async throws {
        let encodedId = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let request = try makeRequest(path: "/api/sessions/\(encodedId)", method: "DELETE")
        _ = try await perform(request: request)
    }

    /// Goi listSessions va tra ve so luong phien de kiem tra ket noi.
    public func checkConnection() async throws -> Int {
        let sessions = try await listSessions()
        return sessions.count
    }

    // MARK: - Private Helpers

    func makeRequest(path: String, method: String, body: Data? = nil) throws -> URLRequest {
        guard !baseURL.isEmpty, !token.isEmpty else {
            throw APIError.missingConfiguration
        }

        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10.0
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

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw APIError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return (data, httpResponse)
    }
}
