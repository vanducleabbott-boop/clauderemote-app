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
    let url: URL
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

        let connection = TerminalConnection(url: url)
        coordinator.connection = connection
        coordinator.terminalView = terminalView

        connection.onData = { [weak terminalView] data in
            terminalView?.feed(byteArray: ArraySlice([UInt8](data)))
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

        if let accessoryProvider = accessoryProvider {
            terminalView.inputAccessoryView = accessoryProvider(terminalView, connection)
        }

        connection.connect()

        DispatchQueue.main.async {
            terminalView.becomeFirstResponder()
        }

        return terminalView
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
            connection?.reconnectNow()
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
