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
        XCTAssertFalse(view.isWheelScrollEnabled)
    }

    /// Claude fullscreen bat alt screen + chuot SGR -> bat vuot con lan; tat chuot -> tat
    func testWheelFollowsMouseMode() {
        let view = RemoteTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.feed(text: "\u{1B}[?1049h\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h")
        XCTAssertTrue(view.isWheelScrollEnabled)
        view.feed(text: "\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l\u{1B}[?1049l")
        XCTAssertFalse(view.isWheelScrollEnabled)
    }

    /// Ma con lan SGR dung chuan: len = 64, xuong = 65
    func testWheelEncoding() {
        let view = RemoteTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.feed(text: "\u{1B}[?1000h\u{1B}[?1006h")
        let terminal = view.getTerminal()
        XCTAssertEqual(terminal.encodeButton(button: 4, release: false, shift: false, meta: false, control: false), 64)
        XCTAssertEqual(terminal.encodeButton(button: 5, release: false, shift: false, meta: false, control: false), 65)
    }
}
