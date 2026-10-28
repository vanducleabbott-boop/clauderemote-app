//
//  ChatSession.swift
//  ClaudeRemote
//
//  1 cuoc chat dang mo: noi WebSocket /ws/chat/:id?since=<seq>, giu danh sach su kien theo id
//  (su kien cap nhat giu nguyen vi tri), tu noi lai khi mat mang / quay lai app.
//  Luu tam su kien vao Caches de mo lai hien ngay, chi tai phan moi.
//

import Foundation
import Combine

@MainActor
final class ChatSession: ObservableObject {
    @Published private(set) var meta: ChatMeta
    @Published private(set) var events: [ChatEvent] = []
    @Published private(set) var connected = false

    private let api: ServerAPI
    private var index: [String: Int] = [:]
    private var maxSeq = 0
    private var task: URLSessionWebSocketTask?
    private var generation = 0
    private var retryDelay: Double = 1
    private var pingTimer: Timer?
    private var saveWork: DispatchWorkItem?
    private var active = false
    private var loginObserver: NSObjectProtocol?

    private static let socketSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    init(meta: ChatMeta, api: ServerAPI) {
        self.meta = meta
        self.api = api
        loadCache()
    }

    // MARK: - Ket noi

    func start() {
        active = true
        if loginObserver == nil {
            loginObserver = NotificationCenter.default.addObserver(
                forName: CloudflareAccess.didLoginNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reconnectNow()
            }
        }
        if task == nil { connect() }
    }

    func stop() {
        active = false
        if let observer = loginObserver {
            NotificationCenter.default.removeObserver(observer)
            loginObserver = nil
        }
        disconnect()
        saveCache()
    }

    /// Quay lai app: ping thu, khong duoc thi noi lai ngay
    func ensureConnected() {
        guard active else { return }
        guard let task = task else { connect(); return }
        task.sendPing { [weak self] error in
            guard error != nil else { return }
            Task { @MainActor in self?.reconnectNow() }
        }
    }

    private func reconnectNow() {
        disconnect()
        retryDelay = 1
        connect()
    }

    private func disconnect() {
        generation += 1
        pingTimer?.invalidate()
        pingTimer = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        connected = false
    }

    private func connect() {
        guard active, let url = api.chatSocketURL(chatId: meta.id, since: maxSeq) else { return }
        generation += 1
        let gen = generation
        var req = URLRequest(url: url)
        CloudflareAccess.apply(to: &req)
        let task = Self.socketSession.webSocketTask(with: req)
        task.maximumMessageSize = 64 * 1024 * 1024
        self.task = task
        task.resume()
        receive(task, gen)

        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.ensureConnected() }
        }
    }

    private func receive(_ task: URLSessionWebSocketTask, _ gen: Int) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self, gen == self.generation else { return }
                switch result {
                case .success(let message):
                    var data: Data?
                    switch message {
                    case .string(let s): data = s.data(using: .utf8)
                    case .data(let d): data = d
                    @unknown default: break
                    }
                    if let data = data, let msg = try? JSONDecoder().decode(ChatSocketMessage.self, from: data) {
                        self.handle(msg)
                    }
                    self.receive(task, gen)
                case .failure:
                    if CloudflareAccess.isAccessResponse(task.response, data: nil) || CloudflareAccess.cookie == nil {
                        CloudflareAccess.clear()
                        if !CloudflareAccess.shared.showLogin, let url = ServerAPI.lastBaseURL {
                            CloudflareAccess.shared.requestLogin(baseURL: url)
                        }
                        self.retryDelay = max(self.retryDelay, 5)
                    }
                    self.scheduleReconnect(gen)
                }
            }
        }
    }

    private func scheduleReconnect(_ gen: Int) {
        guard gen == generation else { return }
        connected = false
        task = nil
        pingTimer?.invalidate()
        guard active else { return }
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 15)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.active, self.task == nil else { return }
            self.connect()
        }
    }

    // MARK: - Su kien

    private func handle(_ msg: ChatSocketMessage) {
        if let chat = msg.chat, chat != meta { meta = chat }
        switch msg.type {
        case "sync":
            connected = true
            retryDelay = 1
            if msg.reset == true {
                events = []
                index = [:]
                maxSeq = 0
            }
            apply(msg.events ?? [])
        case "event":
            if let e = msg.event { apply([e]) }
        default:
            break
        }
    }

    func apply(_ incoming: [ChatEvent]) {
        guard !incoming.isEmpty else { return }
        var list = events
        for e in incoming {
            maxSeq = max(maxSeq, e.seq)
            if let i = index[e.id] {
                list[i] = e
            } else {
                index[e.id] = list.count
                list.append(e)
            }
        }
        events = list
        scheduleSave()
    }

    /// Cap nhat tam tren may (vd vua bam Cho phep) truoc khi server gui lai
    func updateLocally(_ id: String, _ change: (inout ChatEvent) -> Void) {
        guard let i = index[id] else { return }
        change(&events[i])
    }

    func setMeta(_ m: ChatMeta) {
        meta = m
    }

    // MARK: - Luu tam

    private var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(meta.id + ".json")
    }

    private struct Cache: Codable {
        let events: [ChatEvent]
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        events = cache.events
        for (i, e) in events.enumerated() {
            index[e.id] = i
            maxSeq = max(maxSeq, e.seq)
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveCache() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private func saveCache() {
        saveWork?.cancel()
        saveWork = nil
        let url = cacheURL
        guard let data = try? JSONEncoder().encode(Cache(events: events)) else { return }
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    static func removeCache(chatId: String) {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Chats", isDirectory: true)
            .appendingPathComponent(chatId + ".json")
        try? FileManager.default.removeItem(at: url)
    }
}
