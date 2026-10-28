//
//  ChatAPI.swift
//  ClaudeRemote
//
//  Giao dien chat: server chay claude / agy tren PC, app chi gui tin va hien su kien.
//  - GET/POST /api/chats, GET/PATCH/DELETE /api/chats/:id
//  - POST /api/chats/:id/messages {text, turn?} | /permission | /interrupt
//  - POST /api/chats/:id/turns, PUT /api/chats/:id/turns/N/upload?name=  (gui file)
//  - GET  /api/chats/:id/open?path=   (mo file tren PC)
//  - GET  /api/claude-history         (phien Claude cu tren PC)
//  - WS   /ws/chat/:id?since=<seq>
//

import Foundation

// MARK: - Models

public struct ChatMeta: Codable, Identifiable, Equatable {
    public let id: String
    public var name: String
    public let cwd: String
    public let tool: String
    public var mode: String
    public var status: String
    public let createdAt: String?
    public var updatedAt: String?
    public var seq: Int?
    public var preview: String?
    /// So luot da xong + so file ket qua luot cuoi (BackgroundWatcher bao "da xong")
    public var turnsDone: Int? = nil
    public var lastFiles: Int? = nil

    public var isBusy: Bool { status != "idle" }
    public var toolName: String { tool == "agy" ? "agy" : "Claude" }
}

public struct ChatFile: Codable, Equatable, Hashable, Identifiable {
    public let name: String
    public let size: Int64?
    public let path: String?
    /// Thoi diem sua tren PC (ms) -> file sua lai thi tai ban moi
    public var mtime: Double? = nil
    public var id: String { path ?? name }
}

public struct ChatQuestion: Codable, Equatable {
    public struct Option: Codable, Equatable {
        public let label: String
        public let description: String?
    }
    public let question: String
    public let header: String?
    public let multiSelect: Bool?
    public let options: [Option]
}

/// Su kien chat; kind: user | text | tool | permission | files | result | notice
public struct ChatEvent: Codable, Identifiable, Equatable {
    public let id: String
    public var seq: Int
    public let kind: String
    public var ts: String?
    // user / text / notice
    public var text: String?
    public var streaming: Bool?
    public var files: [ChatFile]?
    // tool / permission
    public var name: String?
    public var title: String?
    public var detail: String?
    public var path: String?
    public var status: String?
    public var output: String?
    public var requestId: String?
    public var tool: String?
    public var questions: [ChatQuestion]?
    public var answers: [String: String]?
    // result
    public var ok: Bool?
    public var durationMs: Int?
    public var error: String?
    // files
    public var turn: Int?
    public var folder: String?

    public init(id: String, seq: Int, kind: String, text: String? = nil, title: String? = nil, status: String? = nil) {
        self.id = id
        self.seq = seq
        self.kind = kind
        self.text = text
        self.title = title
        self.status = status
    }
}

public struct ChatDetail: Decodable {
    public let meta: ChatMeta
    public let events: [ChatEvent]

    public init(from decoder: Decoder) throws {
        meta = try ChatMeta(from: decoder)
        let c = try decoder.container(keyedBy: Keys.self)
        events = try c.decode([ChatEvent].self, forKey: .events)
    }

    enum Keys: String, CodingKey { case events }
}

/// Tin tu WebSocket: sync (luc noi) / event (them-cap nhat) / chat (trang thai)
public struct ChatSocketMessage: Decodable {
    public let type: String
    public let chat: ChatMeta?
    public let events: [ChatEvent]?
    public let event: ChatEvent?
    public let reset: Bool?
}

/// Lenh "/" goi y trong o nhap
public struct SlashCommand: Codable, Identifiable, Equatable {
    public let name: String
    public let desc: String
    /// Can go them chu sau lenh (vd /model sonnet)
    public let args: Bool?
    public let skill: Bool?
    public var id: String { name }

    /// Lenh khop chu dang go (bo dau "/"): bat dau bang truoc, chua sau
    public static func filter(_ all: [SlashCommand], draft: String) -> [SlashCommand] {
        guard draft.hasPrefix("/"), !draft.contains(where: { $0.isWhitespace }) else { return [] }
        let q = draft.dropFirst().lowercased()
        if q.isEmpty { return all }
        let starts = all.filter { $0.name.lowercased().hasPrefix(q) }
        let contains = all.filter { !$0.name.lowercased().hasPrefix(q) && $0.name.lowercased().contains(q) }
        let result = starts + contains
        // Go du ten lenh roi thi an goi y
        if result.count == 1, result[0].name.lowercased() == q { return [] }
        return result
    }
}

public struct ClaudeHistoryItem: Codable, Identifiable, Equatable {
    public let sessionId: String
    public let cwd: String
    public let title: String
    public let lastPrompt: String?
    public let updatedAt: String?
    public var id: String { sessionId }
}

public struct CreatedTurn: Codable {
    public let turn: Int
    public let folder: String?
}

public enum PermissionDecision: String {
    case allow
    case always
    case deny
}

/// Che do quyen theo cong cu (giong Shift+Tab tren PC)
public struct ChatMode: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String

    public static func modes(for tool: String) -> [ChatMode] {
        if tool == "agy" {
            return [
                ChatMode(id: "skip", title: "Tự động", subtitle: "Tự chạy mọi thứ, không hỏi", icon: "bolt.fill"),
                ChatMode(id: "accept-edits", title: "Tự sửa file", subtitle: "Tự sửa file, việc khác bị chặn", icon: "pencil"),
                ChatMode(id: "plan", title: "Lập kế hoạch", subtitle: "Chỉ đọc và lên kế hoạch", icon: "list.bullet.clipboard")
            ]
        }
        return [
            ChatMode(id: "default", title: "Hỏi trước", subtitle: "Hỏi bạn trước khi sửa file, chạy lệnh", icon: "hand.raised"),
            ChatMode(id: "acceptEdits", title: "Tự sửa file", subtitle: "Tự sửa file, vẫn hỏi khi chạy lệnh", icon: "pencil"),
            ChatMode(id: "bypassPermissions", title: "Tự động", subtitle: "Tự chạy mọi thứ, không hỏi", icon: "bolt.fill"),
            ChatMode(id: "plan", title: "Lập kế hoạch", subtitle: "Chỉ đọc và lên kế hoạch", icon: "list.bullet.clipboard")
        ]
    }

    public static func find(_ id: String, tool: String) -> ChatMode {
        modes(for: tool).first { $0.id == id } ?? ChatMode(id: id, title: id, subtitle: "", icon: "questionmark")
    }
}

// MARK: - API

extension ServerAPI {
    /// Upload/tai file lon can timeout dai hon
    private static let transferSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }()

    public func listChats() async throws -> [ChatMeta] {
        let (data, _) = try await perform(request: try makeRequest(path: "/api/chats", method: "GET"))
        return try decode([ChatMeta].self, data)
    }

    public func createChat(cwd: String, name: String, tool: String, mode: String) async throws -> ChatMeta {
        let body = try json(["cwd": cwd, "name": name, "tool": tool, "mode": mode])
        let (data, _) = try await perform(request: try makeRequest(path: "/api/chats", method: "POST", body: body))
        return try decode(ChatMeta.self, data)
    }

    /// Mo lai phien Claude cu tren PC (nap lich su, gui tin se tiep tuc phien do)
    public func resumeClaudeSession(_ item: ClaudeHistoryItem) async throws -> ChatMeta {
        let body = try json(["resumeFrom": item.sessionId, "name": item.title])
        var request = try makeRequest(path: "/api/chats", method: "POST", body: body)
        request.timeoutInterval = 60
        let (data, _) = try await perform(request: request, session: Self.transferSession)
        return try decode(ChatMeta.self, data)
    }

    public func getChat(id: String) async throws -> ChatDetail {
        var request = try makeRequest(path: "/api/chats/\(id)", method: "GET")
        request.timeoutInterval = 60
        let (data, _) = try await perform(request: request, session: Self.transferSession)
        return try decode(ChatDetail.self, data)
    }

    public func deleteChat(id: String) async throws {
        _ = try await perform(request: try makeRequest(path: "/api/chats/\(id)", method: "DELETE"))
    }

    @discardableResult
    public func updateChat(id: String, name: String? = nil, mode: String? = nil) async throws -> ChatMeta {
        var obj: [String: Any] = [:]
        if let name = name { obj["name"] = name }
        if let mode = mode { obj["mode"] = mode }
        let (data, _) = try await perform(request: try makeRequest(path: "/api/chats/\(id)", method: "PATCH", body: try json(obj)))
        return try decode(ChatMeta.self, data)
    }

    public func sendMessage(chatId: String, text: String, turn: Int?) async throws {
        var obj: [String: Any] = ["text": text]
        if let turn = turn { obj["turn"] = turn }
        _ = try await perform(request: try makeRequest(path: "/api/chats/\(chatId)/messages", method: "POST", body: try json(obj)))
    }

    public func answerPermission(chatId: String, requestId: String, decision: PermissionDecision, answers: [String: String]? = nil) async throws {
        var obj: [String: Any] = ["requestId": requestId, "decision": decision.rawValue]
        if let answers = answers { obj["answers"] = answers }
        _ = try await perform(request: try makeRequest(path: "/api/chats/\(chatId)/permission", method: "POST", body: try json(obj)))
    }

    public func interrupt(chatId: String) async throws {
        _ = try await perform(request: try makeRequest(path: "/api/chats/\(chatId)/interrupt", method: "POST", body: try json([:])))
    }

    public func claudeHistory(limit: Int = 80) async throws -> [ClaudeHistoryItem] {
        let (data, _) = try await perform(request: try makeRequest(path: "/api/claude-history?limit=\(limit)", method: "GET"))
        return try decode([ClaudeHistoryItem].self, data)
    }

    public func commands(chatId: String) async throws -> [SlashCommand] {
        struct Reply: Decodable { let commands: [SlashCommand] }
        let (data, _) = try await perform(request: try makeRequest(path: "/api/chats/\(chatId)/commands", method: "GET"))
        return try decode(Reply.self, data).commands
    }

    public func chatSocketURL(chatId: String, since: Int) -> URL? {
        webSocketURL(path: "/ws/chat/\(chatId)", query: [URLQueryItem(name: "since", value: String(since))])
    }

    // MARK: File

    public func createTurn(chatId: String) async throws -> CreatedTurn {
        let (data, _) = try await perform(request: try makeRequest(path: "/api/chats/\(chatId)/turns", method: "POST"))
        return try decode(CreatedTurn.self, data)
    }

    /// Upload 1 file tu dia (khong nap het vao RAM).
    public func uploadFile(chatId: String, turn: Int, fileURL: URL, name: String) async throws {
        var request = try makeRequest(path: "/api/chats/\(chatId)/turns/\(turn)/upload?name=\(Self.encodeQuery(name))", method: "PUT")
        request.timeoutInterval = 600
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.transferSession.upload(for: request, fromFile: fileURL)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
        _ = try Self.check(response, data: data)
    }

    /// Tai file tren PC ve Caches de xem (dung lai neu da tai cung kich thuoc).
    public func downloadFile(chatId: String, path remotePath: String, size: Int64? = nil, mtime: Double? = nil) async throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileName = remotePath.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? "file"
        // FNV-1a: khoa on dinh giua cac lan mo app (hashValue doi moi lan chay)
        var hash: UInt64 = 0xcbf29ce484222325
        let cacheName = mtime.map { remotePath + "|" + String(Int64($0)) } ?? remotePath
        for byte in cacheName.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        let key = String(hash, radix: 36)
        let local = caches
            .appendingPathComponent("ChatFiles", isDirectory: true)
            .appendingPathComponent(chatId, isDirectory: true)
            .appendingPathComponent(key, isDirectory: true)
            .appendingPathComponent(fileName)

        if let size = size,
           let attrs = try? FileManager.default.attributesOfItem(atPath: local.path),
           (attrs[.size] as? NSNumber)?.int64Value == size {
            return local
        }

        var request = try makeRequest(path: "/api/chats/\(chatId)/open?path=\(Self.encodeQuery(remotePath))", method: "GET")
        request.timeoutInterval = 600
        let tmp: URL
        let response: URLResponse
        do {
            (tmp, response) = try await Self.transferSession.download(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw APIError.httpError(statusCode: 403, message: "Không được mở file ngoài thư mục dự án")
        }
        _ = try Self.check(response, data: nil)

        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: tmp, to: local)
        return local
    }
}
