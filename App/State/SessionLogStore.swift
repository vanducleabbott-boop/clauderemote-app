//
//  SessionLogStore.swift
//  ClaudeRemote
//
//  Luu output terminal cua tung phien tren iPhone (toi da 100MB/phien) de:
//  - mo phien hien ngay lich su, noi lai chi tai phan moi (?since=)
//  - xem lai lich su khi phien khong con tren server.
//
//  Moi phien: <id>.log (byte output tho) + <id>.json (Meta).
//  Bat bien: vi tri tren server cua byte cuoi file = meta.base + kich thuoc file.
//  API metadata chay tren main thread; doc/ghi file chay tren 1 queue noi tiep.
//

import Foundation

final class SessionLogStore {
    static let shared = SessionLogStore()

    static let maxBytes: Int64 = 100 * 1024 * 1024
    /// Vuot maxBytes thi cat con chung nay (bo phan cu nhat) de khong phai cat lien tuc
    static let trimToBytes: Int64 = 80 * 1024 * 1024
    /// Khi mo phien chi nap phan cuoi vao terminal (terminal chi giu 20000 dong)
    static let tailBytes = 8 * 1024 * 1024

    struct Meta: Codable, Identifiable, Equatable {
        let id: String
        var name: String
        var cwd: String
        var tool: String
        var base: Int64
        var updatedAt: Date
        var bytes: Int64 = 0

        enum CodingKeys: String, CodingKey {
            case id, name, cwd, tool, base, updatedAt
        }
    }

    private let dir: URL
    private let queue = DispatchQueue(label: "SessionLogStore.io", qos: .utility)
    private var metas: [String: Meta] = [:]
    private var handles: [String: FileHandle] = [:] // chi dung tren queue
    private var trimming: Set<String> = []          // main thread: dang cat file nao

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("SessionLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        loadMetas()
    }

    // MARK: - Metadata (main thread)

    func meta(for id: String) -> Meta? {
        metas[id]
    }

    func allMetas() -> [Meta] {
        metas.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Vi tri tren server da luu toi (dung cho ?since=), nil neu chua luu gi.
    func resumeOffset(for id: String) -> Int64? {
        guard let m = metas[id] else { return nil }
        return m.base + m.bytes
    }

    /// Xu ly ban tin hello cua server. Tra ve du lieu can feed them vao terminal (dau hieu mat doan), neu co.
    func handleHello(session: Session, offset: Int64, gap: Bool) -> Data? {
        let id = session.id
        guard var m = metas[id] else {
            // Lan dau: file bat dau tu dung vi tri server gui
            let m = Meta(id: id, name: session.name, cwd: session.cwd, tool: session.tool,
                         base: offset, updatedAt: Date(), bytes: 0)
            metas[id] = m
            saveMeta(m)
            return nil
        }

        m.name = session.name
        m.updatedAt = Date()
        var marker: Data? = nil
        if gap || offset != m.base + m.bytes {
            // Server khong con du doan con thieu (bo dem tran) -> danh dau roi noi tiep tu offset
            let note = Data("\r\n\u{1B}[2m[--- thiếu một đoạn khi mất kết nối ---]\u{1B}[0m\r\n".utf8)
            marker = note
            m.bytes += Int64(note.count)
            m.base = offset - m.bytes
            writeAppend(id: id, data: note)
        }
        metas[id] = m
        saveMeta(m)
        return marker
    }

    func append(id: String, data: Data) {
        guard !data.isEmpty, var m = metas[id] else { return }
        m.bytes += Int64(data.count)
        metas[id] = m
        writeAppend(id: id, data: data)
        if m.bytes > Self.maxBytes && !trimming.contains(id) {
            trimming.insert(id)
            trim(id: id)
        }
    }

    /// Doc phan cuoi file (toi da tailBytes) tren queue IO, tra ve tren main.
    func readTail(id: String, completion: @escaping (Data) -> Void) {
        let url = logURL(id)
        queue.async { [weak self] in
            self?.closeHandle(id)
            var result = Data()
            if let fh = try? FileHandle(forReadingFrom: url) {
                let size = (try? fh.seekToEnd()) ?? 0
                let start = size > UInt64(Self.tailBytes) ? size - UInt64(Self.tailBytes) : 0
                try? fh.seek(toOffset: start)
                result = (try? fh.readToEnd()) ?? Data()
                try? fh.close()
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func remove(id: String) {
        metas[id] = nil
        let log = logURL(id), json = metaURL(id)
        queue.async { [weak self] in
            self?.closeHandle(id)
            try? FileManager.default.removeItem(at: log)
            try? FileManager.default.removeItem(at: json)
        }
    }

    // MARK: - Private

    private func logURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).log") }
    private func metaURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).json") }

    private func loadMetas() {
        let decoder = JSONDecoder()
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  var m = try? decoder.decode(Meta.self, from: data) else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: logURL(m.id).path)[.size] as? NSNumber)?.int64Value
            m.bytes = size ?? 0
            metas[m.id] = m
        }
    }

    private func saveMeta(_ m: Meta) {
        let url = metaURL(m.id)
        queue.async {
            if let data = try? JSONEncoder().encode(m) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func writeAppend(id: String, data: Data) {
        let url = logURL(id)
        queue.async { [weak self] in
            guard let self = self else { return }
            let fh: FileHandle
            if let existing = self.handles[id] {
                fh = existing
            } else {
                if !FileManager.default.fileExists(atPath: url.path) {
                    FileManager.default.createFile(atPath: url.path, contents: nil)
                }
                guard let opened = try? FileHandle(forWritingTo: url) else { return }
                _ = try? opened.seekToEnd()
                self.handles[id] = opened
                fh = opened
            }
            try? fh.write(contentsOf: data)
        }
    }

    private func closeHandle(_ id: String) {
        if let fh = handles.removeValue(forKey: id) {
            try? fh.close()
        }
    }

    /// Bo phan dau file, giu lai trimToBytes byte cuoi. Cap nhat base de bat bien van dung.
    private func trim(id: String) {
        let url = logURL(id)
        queue.async { [weak self] in
            guard let self = self else { return }
            self.closeHandle(id)
            var removed: Int64 = 0
            if let fh = try? FileHandle(forReadingFrom: url) {
                let size = Int64((try? fh.seekToEnd()) ?? 0)
                if size > Self.trimToBytes {
                    try? fh.seek(toOffset: UInt64(size - Self.trimToBytes))
                    let keep = (try? fh.readToEnd()) ?? Data()
                    if (try? keep.write(to: url, options: .atomic)) != nil {
                        removed = size - Self.trimToBytes
                    }
                }
                try? fh.close()
            }

            DispatchQueue.main.async {
                self.trimming.remove(id)
                guard removed > 0, var m = self.metas[id] else { return }
                m.base += removed
                m.bytes -= removed
                self.metas[id] = m
                self.saveMeta(m)
            }
        }
    }
}
