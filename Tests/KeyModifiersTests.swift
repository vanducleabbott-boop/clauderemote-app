//
//  KeyModifiersTests.swift
//  Ctrl/Alt dinh va thanh phim.
//

import XCTest
import SwiftTerm
@testable import ClaudeRemote

final class KeyModifiersTests: XCTestCase {
    func testCtrlOnceAppliesToNextKeyOnly() {
        let m = KeyModifiers()
        m.tapCtrl()
        XCTAssertEqual(m.apply(toTyped: Data("r".utf8)), Data([0x12]))   // Ctrl+R
        XCTAssertEqual(m.ctrl, .off)
        XCTAssertEqual(m.apply(toTyped: Data("r".utf8)), Data("r".utf8))
    }

    func testCtrlLockedStaysOn() {
        let m = KeyModifiers()
        m.lockCtrl()
        XCTAssertEqual(m.apply(toTyped: Data("c".utf8)), Data([0x03]))
        XCTAssertEqual(m.apply(toTyped: Data("O".utf8)), Data([0x0F]))
        XCTAssertEqual(m.ctrl, .locked)
        m.tapCtrl()
        XCTAssertEqual(m.ctrl, .off)
    }

    func testAltPrefixesEscape() {
        let m = KeyModifiers()
        m.tapAlt()
        XCTAssertEqual(m.apply(toTyped: Data("p".utf8)), Data([0x1B, 0x70]))  // Alt+P chon model
        XCTAssertEqual(m.alt, .off)
    }

    func testMultiByteInputUntouched() {
        let m = KeyModifiers()
        m.tapCtrl()
        let viet = Data("ệ".utf8)
        XCTAssertEqual(m.apply(toTyped: viet), viet)
        XCTAssertEqual(m.ctrl, .once) // chua dung -> van cho phim tiep theo
    }

    func testSpecialKeysWithModifiers() {
        let m = KeyModifiers()
        XCTAssertEqual(m.apply(toSpecial: .up), [0x1B, 0x5B, 0x41])
        XCTAssertEqual(m.apply(toSpecial: .up, applicationCursor: true), [0x1B, 0x4F, 0x41])
        m.tapCtrl()
        XCTAssertEqual(m.apply(toSpecial: .home), Array("\u{1B}[1;5H".utf8))
        m.tapAlt()
        XCTAssertEqual(m.apply(toSpecial: .pageUp), Array("\u{1B}[5;3~".utf8))
        XCTAssertEqual(m.apply(toSpecial: .pageDown), Array("\u{1B}[6~".utf8))
    }

    func testEnterVariants() {
        let m = KeyModifiers()
        XCTAssertEqual(m.applyToEnter(), [0x0D])
        m.tapAlt()
        XCTAssertEqual(m.applyToEnter(), [0x1B, 0x0D])
        m.tapCtrl()
        XCTAssertEqual(m.applyToEnter(), [0x0A])
    }

    /// Tao thanh phim cho ca claude va agy khong crash (menu phim tat, nut giu)
    func testKeyBarBuilds() {
        let view = RemoteTerminalView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let conn = TerminalConnection(url: URL(string: "ws://127.0.0.1:1/ws/x")!)
        for tool in ["claude", "agy"] {
            let m = KeyModifiers()
            let bar = KeyBar(terminalView: view, connection: conn, modifiers: m, tool: tool)
            bar.layoutIfNeeded()
            m.tapCtrl()
            m.lockAlt()
        }
    }
}
