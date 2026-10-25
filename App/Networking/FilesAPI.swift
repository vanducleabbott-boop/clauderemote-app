//
//  FilesAPI.swift
//  ClaudeRemote
//
//  Gui file theo phien. Tren PC: File xu ly/<Ten phien>/Luot N/{Gui len, Ket qua}
//  - POST /api/sessions/:id/turns                          -> {turn, folder}
//  - PUT  /api/sessions/:id/turns/N/upload?name=<ten>     body = noi dung file
//  - POST /api/sessions/:id/turns/N/submit {message}       -> server go yeu cau vao phien
//  - GET  /api/sessions/:id/files                          -> {folder, turns:[{turn, uploads, results}]}
//  - GET  /api/sessions/:id/turns/N/file?kind=uploads|results&name=<duong dan tuong doi>
//

import Foundation

public struct RemoteFile: Codable, Identifiable, Hashable {
    public let name: String
    public let size: Int64
    public let modifiedAt: String?
    public var id: String { name }
}

public struct FileTurn: Codable, Identifiable, Equatable {
    public let turn: Int
    public let uploads: [RemoteFile]
    public let results: [RemoteFile]
    public var id: Int { turn }
}

public struct FilesListing: Codable, Equatable {
    public let folder: String?
    public let turns: [FileTurn]
}

public struct CreatedTurn: Codable {
    public let turn: Int
    public let folder: String?
}

public struct SubmitResult: Codable {
    public let ok: Bool
    public let sent: Bool
    public let prompt: String?
}

public enum FileKind: String {
    case uploads
    case results
}

extension ServerAPI {
    /// Upload/tai file lon can timeout dai hon 10s cua API thuong
    private static let transferSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }()

    private static let queryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#/"))

    private static func encodeQuery(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
    }

    public func listFiles(sessionId: String) async throws -> FilesListing {
        let request = try makeRequest(path: "/api/sessions/\(sessionId)/files", method: "GET")
        let (data, _) = try await perform(request: request)
        do {
            return try JSONDecoder().decode(FilesListing.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    public func createTurn(sessionId: String) async throws -> CreatedTurn {
        let request = try makeRequest(path: "/api/sessions/\(sessionId)/turns", method: "POST")
        let (data, _) = try await perform(request: request)
        do {
            return try JSONDecoder().decode(CreatedTurn.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Upload 1 file tu dia (khong nap het vao RAM).
    public func uploadFile(sessionId: String, turn: Int, fileURL: URL, name: String) async throws {
        var request = try makeRequest(
            path: "/api/sessions/\(sessionId)/turns/\(turn)/upload?name=\(Self.encodeQuery(name))",
            method: "PUT"
        )
        request.timeoutInterval = 600
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.transferSession.upload(for: request, fromFile: fileURL)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, message: String(data: data, encoding: .utf8))
        }
    }

    public func submitTurn(sessionId: String, turn: Int, message: String) async throws -> SubmitResult {
        let body = try JSONSerialization.data(withJSONObject: ["message": message])
        let request = try makeRequest(path: "/api/sessions/\(sessionId)/turns/\(turn)/submit", method: "POST", body: body)
        let (data, _) = try await perform(request: request)
        do {
            return try JSONDecoder().decode(SubmitResult.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Tai file ve Caches (dung lai neu da tai va cung kich thuoc), tra ve URL tren may de xem.
    public func downloadFile(sessionId: String, turn: Int, kind: FileKind, file: RemoteFile) async throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches
            .appendingPathComponent("SessionFiles", isDirectory: true)
            .appendingPathComponent(sessionId, isDirectory: true)
            .appendingPathComponent("\(turn)-\(kind.rawValue)", isDirectory: true)
        let local = file.name.split(separator: "/").reduce(dir) { $0.appendingPathComponent(String($1)) }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: local.path),
           (attrs[.size] as? NSNumber)?.int64Value == file.size {
            return local
        }

        var request = try makeRequest(
            path: "/api/sessions/\(sessionId)/turns/\(turn)/file?kind=\(kind.rawValue)&name=\(Self.encodeQuery(file.name))",
            method: "GET"
        )
        request.timeoutInterval = 600

        let tmp: URL
        let response: URLResponse
        do {
            (tmp, response) = try await Self.transferSession.download(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200...299).contains(http.statusCode) else {
            throw APIError.httpError(statusCode: http.statusCode, message: nil)
        }

        try FileManager.default.createDirectory(at: local.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: local)
        try FileManager.default.moveItem(at: tmp, to: local)
        return local
    }
}
