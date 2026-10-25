//
//  TerminalViewTests.swift
//  Chay tren iOS Simulator: tao terminal giong luc mo phien (ban 1.8 crash o day).
//

import XCTest
import SwiftTerm
@testable import ClaudeRemote

final class TerminalViewTests: XCTestCase {
    /// Tao view nhu TerminalHost.makeUIView: khong duoc crash
    func testCreateLikeOpeningSession() {
        let view = RemoteTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.changeScrollback(20000)
        view.feed(byteArray: [0x1B, 0x63]) // RIS khi noi lai server cu
        view.feed(text: "xin chao\r\n")
        XCTAssertTrue(view.isNativeScrollEnabled)
    }
}

final class NativeScrollTests: XCTestCase {
    /// Claude fullscreen (alt screen) -> tat cuon san co (tranh logo hien 2 lan); thoat -> bat lai
    func testNativeScrollOffInAltScreen() {
        let view = RemoteTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        XCTAssertTrue(view.isNativeScrollEnabled)
        view.feed(text: "\u{1B}[?1049h")
        XCTAssertFalse(view.isNativeScrollEnabled)
        view.feed(text: "\u{1B}[?1000h\u{1B}[?1006h")
        XCTAssertFalse(view.isNativeScrollEnabled)
        view.feed(text: "\u{1B}[?1000l\u{1B}[?1006l\u{1B}[?1049l")
        XCTAssertTrue(view.isNativeScrollEnabled)
    }

    /// Giao dien co dien co bat chuot (man hinh chinh): van cuon tai cho, khong gui gi sang PC
    func testMouseModeOnMainBufferStillScrollsLocally() {
        let view = RemoteTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        var sent: [UInt8] = []
        let spy = SendSpy { sent += $0 }
        view.terminalDelegate = spy
        view.feed(text: "\u{1B}[?1000h\u{1B}[?1006h")
        for i in 0..<200 { view.feed(text: "dong \(i)\r\n") }
        XCTAssertTrue(view.isNativeScrollEnabled)
        XCTAssertTrue(sent.isEmpty)
        withExtendedLifetime(spy) {}
    }
}

private final class SendSpy: NSObject, TerminalViewDelegate {
    let onSend: ([UInt8]) -> Void
    init(_ onSend: @escaping ([UInt8]) -> Void) { self.onSend = onSend }
    func send(source: TerminalView, data: ArraySlice<UInt8>) { onSend(Array(data)) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
