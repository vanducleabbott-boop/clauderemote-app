//
//  TerminalConnection.swift
//  ClaudeRemote
//
//  Quan ly ket noi WebSocket hai chieu toi phien terminal tren server.
//

import Foundation

public final class TerminalConnection: NSObject, URLSessionWebSocketDelegate {
    public enum State: Equatable {
        case connecting
        case connected
        case disconnected(reason: String?)
    }

    public let url: URL

    /// Du lieu terminal da gom lai, luon goi tren main thread.
    public var onData: ((Data) -> Void)?
    /// Goi tren main thread ngay truoc du lieu dau tien cua moi lan ket noi
    /// (server se phat lai toan bo bo dem -> can xoa terminal de khong in lap).
    public var onReset: (() -> Void)?
    public var onState: ((State) -> Void)?

    public private(set) var state: State = .disconnected(reason: nil) {
        didSet {
            guard state != oldValue else { return }
            let currentState = state
            if Thread.isMainThread {
                self.onState?(currentState)
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.onState?(currentState)
                }
            }
        }
    }

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var isManuallyClosed: Bool = false
    private var retryWorkItem: DispatchWorkItem?
    private var pingTimer: Timer?
    private var retryDelay: TimeInterval = 1.0
    private let minRetryDelay: TimeInterval = 1.0
    private let maxRetryDelay: TimeInterval = 5.0

    /// Gom cac tin nho thanh 1 lan feed (~1 frame) thay vi nhay sang main thread cho tung tin
    private let flushInterval: TimeInterval = 0.012
    /// Bo dem replay cua server (2048K ky tu, nhieu ky tu khung 3 byte) vuot xa 1MB mac dinh
    private let maxMessageSize = 32 * 1024 * 1024
    private let pingInterval: TimeInterval = 20

    // Phan duoi day duoc truy cap tu queue cua URLSession -> bao ve bang lock
    private let lock = NSLock()
    private var generation: Int = 0
    private var pending = Data()
    private var pendingReset = false
    private var receivedFirst = false
    private var flushScheduled = false

    public init(url: URL) {
        self.url = url
        super.init()
    }

    deinit {
        pingTimer?.invalidate()
        retryWorkItem?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        session?.invalidateAndCancel()
    }

    // MARK: - Public Controls

    /// Bat dau ket noi toi WebSocket server.
    public func connect() {
        cleanUpCurrentConnection()

        isManuallyClosed = false
        updateState(.connecting)

        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        let newSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = newSession

        let newTask = newSession.webSocketTask(with: url)
        newTask.maximumMessageSize = maxMessageSize
        self.task = newTask

        lock.lock()
        let gen = generation
        lock.unlock()

        newTask.resume()
        receiveLoop(for: newTask, generation: gen)
    }

    /// Chu dong noi lai ngay lap tuc.
    public func reconnectNow() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        retryDelay = minRetryDelay
        isManuallyClosed = false
        connect()
    }

    /// Khi app tro lai foreground: ket noi con song thi giu nguyen (khong tai lai bo dem),
    /// chi noi lai khi da mat hoac ping khong tra loi trong 3s.
    public func ensureAlive() {
        guard !isManuallyClosed else { return }
        guard state == .connected, let task = task else {
            reconnectNow()
            return
        }

        var answered = false
        let timeout = DispatchWorkItem { [weak self, weak task] in
            guard let self = self, !answered, let task = task, self.task === task else { return }
            self.reconnectNow()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)

        task.sendPing { [weak self, weak task] error in
            DispatchQueue.main.async {
                answered = true
                timeout.cancel()
                guard let self = self, let task = task, self.task === task else { return }
                if error != nil {
                    self.reconnectNow()
                }
            }
        }
    }

    /// Dong ket noi thu cong va khong tu dong noi lai.
    public func close() {
        isManuallyClosed = true
        retryWorkItem?.cancel()
        retryWorkItem = nil

        cleanUpCurrentConnection()
        updateState(.disconnected(reason: nil))
    }

    /// Gui du lieu binary tho (.data) toi terminal server.
    public func send(bytes: Data) {
        guard let task = self.task, state == .connected else { return }
        task.send(.data(bytes)) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.handleFailure(reason: error.localizedDescription)
                }
            }
        }
    }

    /// Gui chuoi text (.string) toi terminal server (dung cho tin nhan dieu khien resize).
    public func sendText(_ text: String) {
        guard let task = self.task, state == .connected else { return }
        task.send(.string(text)) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.handleFailure(reason: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Private Connection Logic

    private func updateState(_ newState: State) {
        if Thread.isMainThread {
            self.state = newState
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.state = newState
            }
        }
    }

    private func markConnected() {
        retryDelay = minRetryDelay
        updateState(.connected)
        startPing()
    }

    private func cleanUpCurrentConnection() {
        stopPing()

        lock.lock()
        generation += 1
        pending.removeAll(keepingCapacity: false)
        pendingReset = false
        receivedFirst = false
        lock.unlock()

        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    /// Nhan tin tren queue cua URLSession, chi gom vao bo dem; main thread feed theo nhip flushInterval.
    private func receiveLoop(for currentTask: URLSessionWebSocketTask, generation gen: Int) {
        currentTask.receive { [weak self, weak currentTask] result in
            guard let self = self, let currentTask = currentTask else { return }

            switch result {
            case .success(let message):
                let chunk: Data
                switch message {
                case .data(let data):
                    chunk = data
                case .string(let text):
                    chunk = Data(text.utf8)
                @unknown default:
                    chunk = Data()
                }

                self.lock.lock()
                guard gen == self.generation else {
                    self.lock.unlock()
                    return
                }
                if !self.receivedFirst {
                    self.receivedFirst = true
                    self.pendingReset = true
                }
                self.pending.append(chunk)
                let needSchedule = !self.flushScheduled
                self.flushScheduled = true
                self.lock.unlock()

                if needSchedule {
                    DispatchQueue.main.asyncAfter(deadline: .now() + self.flushInterval) { [weak self] in
                        self?.flush(generation: gen)
                    }
                }
                self.receiveLoop(for: currentTask, generation: gen)

            case .failure(let error):
                DispatchQueue.main.async {
                    guard self.task === currentTask else { return }
                    self.handleFailure(reason: error.localizedDescription)
                }
            }
        }
    }

    private func flush(generation gen: Int) {
        lock.lock()
        flushScheduled = false
        guard gen == generation, !pending.isEmpty else {
            lock.unlock()
            return
        }
        let data = pending
        let reset = pendingReset
        pending = Data()
        pendingReset = false
        lock.unlock()

        guard !isManuallyClosed else { return }
        if state != .connected {
            markConnected()
        }
        if reset {
            onReset?()
        }
        onData?(data)
    }

    private func startPing() {
        stopPing()
        let timer = Timer(timeInterval: pingInterval, repeats: true) { [weak self] _ in
            guard let self = self, let task = self.task, self.state == .connected else { return }
            task.sendPing { [weak self, weak task] error in
                guard let error = error else { return }
                DispatchQueue.main.async {
                    guard let self = self, let task = task, self.task === task else { return }
                    self.handleFailure(reason: error.localizedDescription)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pingTimer = timer
    }

    private func stopPing() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func handleFailure(reason: String) {
        guard !isManuallyClosed else { return }
        handleDisconnect(reason: reason)
    }

    private func handleDisconnect(reason: String?) {
        guard !isManuallyClosed else { return }

        // Neu da o trang thai disconnected roi thi khong kich hoat lai timer
        if case .disconnected = state {
            return
        }

        cleanUpCurrentConnection()
        updateState(.disconnected(reason: reason))
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !isManuallyClosed else { return }
        retryWorkItem?.cancel()

        let delay = retryDelay
        // Tang dan toi muc toi da 5s
        retryDelay = min(retryDelay * 1.5, maxRetryDelay)

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self, !self.isManuallyClosed else { return }
            self.connect()
        }
        self.retryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // MARK: - URLSessionWebSocketDelegate

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.task === webSocketTask, !self.isManuallyClosed else { return }
            self.markConnected()
        }
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonStr: String?
        if let reason = reason, let str = String(data: reason, encoding: .utf8), !str.isEmpty {
            reasonStr = str
        } else {
            reasonStr = nil
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.task === webSocketTask else { return }
            self.handleDisconnect(reason: reasonStr)
        }
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.task === task else { return }
            if let error = error {
                self.handleFailure(reason: error.localizedDescription)
            }
        }
    }
}
