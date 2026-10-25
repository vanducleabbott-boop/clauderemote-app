//
//  KeyModifiers.swift
//  ClaudeRemote
//
//  Ctrl / Alt "dinh" cho iPhone (khong giu duoc 2 phim cung luc):
//  - cham 1 lan: ap dung cho 1 phim go tiep theo (ban phim iOS hoac thanh phim) roi tu tat
//  - giu: khoa (ap dung cho moi phim) toi khi cham lai
//

import Foundation

final class KeyModifiers {
    enum State {
        case off
        case once
        case locked
    }

    private(set) var ctrl: State = .off { didSet { if ctrl != oldValue { onChange?() } } }
    private(set) var alt: State = .off { didSet { if alt != oldValue { onChange?() } } }

    /// Goi tren main khi trang thai doi (cap nhat mau nut)
    var onChange: (() -> Void)?

    var isActive: Bool { ctrl != .off || alt != .off }

    // MARK: - Nut Ctrl / Alt

    /// Cham: tat -> 1 lan; 1 lan hoac khoa -> tat
    func tapCtrl() { ctrl = (ctrl == .off) ? .once : .off }
    func tapAlt() { alt = (alt == .off) ? .once : .off }
    /// Giu: khoa
    func lockCtrl() { ctrl = .locked }
    func lockAlt() { alt = .locked }

    /// Sau khi 1 phim da dung modifier: tat cac modifier "1 lan"
    private func consume() {
        if ctrl == .once { ctrl = .off }
        if alt == .once { alt = .off }
    }

    // MARK: - Ap dung

    /// Ky tu go tu ban phim iOS (1 byte ASCII) -> Ctrl/Alt + ky tu. Du lieu khac giu nguyen.
    func apply(toTyped data: Data) -> Data {
        guard isActive, data.count == 1, let byte = data.first else { return data }
        var out = Data()
        var key = byte
        if ctrl != .off, let c = Self.controlCode(for: byte) {
            key = c
        }
        if alt != .off {
            out.append(0x1B)
        }
        out.append(key)
        consume()
        return out
    }

    /// Phim dac biet tren thanh phim (mui ten, Home/End, PgUp/PgDn) theo kieu xterm: CSI 1;<m>X
    /// m = 1 + 2*alt + 4*ctrl. Khong co modifier thi tra ve chuoi thuong.
    func apply(toSpecial key: SpecialKey, applicationCursor: Bool = false) -> [UInt8] {
        var m = 1
        if alt != .off { m += 2 }
        if ctrl != .off { m += 4 }
        defer { if m > 1 { consume() } }
        return key.sequence(modifier: m, applicationCursor: applicationCursor)
    }

    /// Enter: Alt+Enter = xuong dong (khong gui) trong Claude/agy
    func applyToEnter() -> [UInt8] {
        if alt != .off {
            consume()
            return [0x1B, 0x0D]
        }
        if ctrl != .off {
            consume()
            return [0x0A] // Ctrl+J = xuong dong
        }
        return [0x0D]
    }

    static func controlCode(for byte: UInt8) -> UInt8? {
        switch byte {
        case 0x61...0x7A: return byte - 0x60          // a-z
        case 0x41...0x5A: return byte - 0x40          // A-Z
        case 0x40, 0x20, 0x32: return 0x00            // @ space 2
        case 0x5B, 0x33: return 0x1B                  // [ 3
        case 0x5C, 0x34: return 0x1C                  // \ 4
        case 0x5D, 0x35: return 0x1D                  // ] 5
        case 0x5E, 0x36: return 0x1E                  // ^ 6
        case 0x5F, 0x2D, 0x37: return 0x1F            // _ - 7
        case 0x3F, 0x38: return 0x7F                  // ? 8
        default: return nil
        }
    }
}

enum SpecialKey {
    case up, down, right, left, home, end, pageUp, pageDown

    /// applicationCursor: mui ten khong modifier dung ESC O x (giong SwiftTerm)
    func sequence(modifier m: Int, applicationCursor: Bool = false) -> [UInt8] {
        let esc: UInt8 = 0x1B
        switch self {
        case .up, .down, .right, .left, .home, .end:
            let final: UInt8
            switch self {
            case .up: final = 0x41
            case .down: final = 0x42
            case .right: final = 0x43
            case .left: final = 0x44
            case .home: final = 0x48
            default: final = 0x46
            }
            if m > 1 {
                return [esc, 0x5B, 0x31, 0x3B] + Array(String(m).utf8) + [final]
            }
            return [esc, applicationCursor ? 0x4F : 0x5B, final]
        case .pageUp, .pageDown:
            let n: UInt8 = self == .pageUp ? 0x35 : 0x36
            if m > 1 {
                return [esc, 0x5B, n, 0x3B] + Array(String(m).utf8) + [0x7E]
            }
            return [esc, 0x5B, n, 0x7E]
        }
    }
}
