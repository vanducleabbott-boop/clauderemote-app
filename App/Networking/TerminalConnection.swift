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

    public var onData: ((Data) -> Void)?
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
    private var retryDelay: TimeInterval = 1.5
    private let minRetryDelay: TimeInterval = 1.5
    private let maxRetryDelay: TimeInterval = 5.0

    public init(url: URL) {
        self.url = url
        super.init()
    }

    deinit {
        close()
    }

    // MARK: - Public Controls

    /// Bat dau ket noi toi WebSocket server.
    public func connect() {
        cleanUpCurrentConnection()

        isManuallyClosed = false
        updateState(.connecting)

        let configuration = URLSessionConfiguration.default
        let newSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = newSession

        let newTask = newSession.webSocketTask(with: url)
        self.task = newTask
        newTask.resume()

        receiveLoop(for: newTask)
    }

    /// Chu dong noi lai ngay lap tuc (vi du khi app tro lai foreground).
    public func reconnectNow() {
        retryWorkItem?.cancel()
        retryWorkItem = nil
        retryDelay = minRetryDelay
        isManuallyClosed = false
        connect()
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

    private func cleanUpCurrentConnection() {
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func receiveLoop(for currentTask: URLSessionWebSocketTask) {
        currentTask.receive { [weak self, weak currentTask] result in
            DispatchQueue.main.async {
                guard let self = self,
                      let currentTask = currentTask,
                      self.task === currentTask,
                      !self.isManuallyClosed else {
                    return
                }

                switch result {
                case .success(let message):
                    if self.state != .connected {
                        self.retryDelay = self.minRetryDelay
                        self.updateState(.connected)
                    }

                    switch message {
                    case .data(let data):
                        self.onData?(data)
                    case .string(let text):
                        if let data = text.data(using: .utf8) {
                            self.onData?(data)
                        }
                    @unknown default:
                        break
                    }

                    self.receiveLoop(for: currentTask)

                case .failure(let error):
                    self.handleFailure(reason: error.localizedDescription)
                }
            }
        }
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
            self.retryDelay = self.minRetryDelay
            self.updateState(.connected)
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
