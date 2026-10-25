//
//  TerminalHost.swift
//  ClaudeRemote
//
//  UIViewRepresentable boc TerminalView cua SwiftTerm va quan ly ket noi TerminalConnection.
//

import SwiftUI
import UIKit
import SwiftTerm

struct TerminalHost: UIViewRepresentable {
    let session: Session
    /// nil = chi xem lich su da luu tren may (phien khong con tren server)
    let url: URL?
    @Binding var state: TerminalConnection.State
    var accessoryProvider: ((TerminalView, TerminalConnection) -> UIView?)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> TerminalView {
        let coordinator = context.coordinator

        let terminalView = TerminalView(frame: .zero)
        terminalView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = UIColor(white: 0.9, alpha: 1)
        terminalView.terminalDelegate = coordinator
        // Mac dinh SwiftTerm chi giu 500 dong -> khong cuon lai duoc dau phien
        terminalView.changeScrollback(20000)

        let logStore = SessionLogStore.shared
        let session = self.session
        let connection = TerminalConnection(url: url ?? URL(string: "about:blank")!)
        coordinator.connection = connection
        coordinator.terminalView = terminalView

        // Noi lai tu vi tri da luu tren may: server chi gui phan moi
        connection.resumeOffset = {
            logStore.resumeOffset(for: session.id)
        }

        connection.onHello = { [weak coordinator, weak terminalView] offset, gap in
            coordinator?.storing = true
            if let marker = logStore.handleHello(session: session, offset: offset, gap: gap) {
                terminalView?.feed(byteArray: ArraySlice(marker))
            }
        }

        connection.onData = { [weak coordinator, weak terminalView] data in
            terminalView?.feed(byteArray: ArraySlice(data))
            if coordinator?.storing == true {
                logStore.append(id: session.id, data: data)
            }
        }

        // Server cu (khong resume) phat lai ca bo dem: gui ESC c (RIS) xoa sach terminal truoc,
        // neu khong noi dung cu bi in chong len nhau; khong luu vi khong biet vi tri
        connection.onReset = { [weak coordinator, weak terminalView] in
            coordinator?.storing = false
            terminalView?.feed(byteArray: [0x1B, 0x63])
        }

        let stateBinding = _state
        connection.onState = { [weak connection, weak terminalView] newState in
            DispatchQueue.main.async {
                stateBinding.wrappedValue = newState
                if newState == .connected {
                    if let terminal = terminalView?.getTerminal(), let connection = connection {
                        let cols = terminal.cols
                        let rows = terminal.rows
                        connection.sendText(ServerAPI.resizeMessage(cols: cols, rows: rows))
                    }
                }
            }
        }

        guard url != nil else {
            // Chi xem: nap lich su tren may, khong ket noi
            let readOnlyState = _state
            DispatchQueue.main.async { readOnlyState.wrappedValue = .disconnected(reason: "chỉ xem lịch sử") }
            Self.feedLocalLog(id: session.id, into: terminalView) {}
            return terminalView
        }

        if let accessoryProvider = accessoryProvider {
            terminalView.inputAccessoryView = accessoryProvider(terminalView, connection)
        }

        // Hien lich su da luu truoc, xong moi ket noi (tranh xen ke du lieu cu/moi)
        Self.feedLocalLog(id: session.id, into: terminalView) { [weak connection] in
            connection?.connect()
        }

        DispatchQueue.main.async {
            terminalView.becomeFirstResponder()
        }

        return terminalView
    }

    /// Doc phan cuoi log tren may roi feed tung khuc 256KB moi vong runloop de giao dien khong dung hinh.
    private static func feedLocalLog(id: String, into terminalView: TerminalView, completion: @escaping () -> Void) {
        SessionLogStore.shared.readTail(id: id) { [weak terminalView] data in
            let chunkSize = 256 * 1024
            func feed(from start: Int) {
                guard let terminalView = terminalView else { return }
                guard start < data.count else {
                    completion()
                    return
                }
                let end = min(start + chunkSize, data.count)
                terminalView.feed(byteArray: ArraySlice(data[start..<end]))
                DispatchQueue.main.async { feed(from: end) }
            }
            feed(from: 0)
        }
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {
        // De trong theo thiet ke
    }

    static func dismantleUIView(_ uiView: TerminalView, coordinator: Coordinator) {
        coordinator.connection?.close()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, TerminalViewDelegate {
        var connection: TerminalConnection?
        weak var terminalView: TerminalView?
        /// true sau khi server gui hello (biet vi tri) -> output duoc luu vao may
        var storing = false

        override init() {
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWillEnterForeground),
                name: UIApplication.willEnterForegroundNotification,
                object: nil
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleWillEnterForeground() {
            guard connection?.url.scheme != "about" else { return }
            // Khong ngat ket noi con song (tranh tai lai 400KB moi lan mo app), chi noi lai neu da chet
            connection?.ensureAlive()
        }

        // MARK: - TerminalViewDelegate

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            // SwiftTerm tu goi khi xoay may / ban phim hien/an => dong thoi la gui resize
            connection?.sendText(ServerAPI.resizeMessage(cols: newCols, rows: newRows))
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            connection?.send(bytes: Data(data))
        }

        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link), UIApplication.shared.canOpenURL(url) else { return }
            UIApplication.shared.open(url)
        }

        func bell(source: TerminalView) {}

        func clipboardCopy(source: TerminalView, content: Data) {
            UIPasteboard.general.string = String(data: content, encoding: .utf8)
        }

        func clipboardRead(source: TerminalView) -> Data? {
            return nil
        }

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
