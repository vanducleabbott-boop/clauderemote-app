//
//  RemoteTerminalView.swift
//  ClaudeRemote
//
//  TerminalView cua SwiftTerm + vuot de cuon khi chuong trinh bat che do chuot.
//
//  Claude Code giao dien fullscreen (/tui fullscreen) ve trong alt screen va tu cuon bang
//  con lan chuot, terminal khong co scrollback. SwiftTerm mac dinh bien vuot thanh "keo chuot"
//  (Claude hieu la boi den chu) nen vuot len khong xem duoc tin cu.
//  O day vuot doc duoc doi thanh su kien con lan (SGR wheel) -> cuon giong lan chuot tren PC.
//  Giao dien co dien (khong bat chuot): vuot cuon scrollback nhu binh thuong.
//

import UIKit
import SwiftTerm

final class RemoteTerminalView: TerminalView {
    /// Optional: SwiftTerm goi mouseModeChanged ngay trong super.init (Terminal.setup dat mouseMode = .off),
    /// luc do pan chua duoc tao -> khong duoc force unwrap (ban 1.8 crash khi mo phien vi cho nay)
    private var wheelPan: UIPanGestureRecognizer?
    private let wheelDelegate = SimultaneousGestureDelegate()
    private var accumulated: CGFloat = 0
    private var momentumTimer: Timer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupWheelPan()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupWheelPan()
    }

    private func setupWheelPan() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleWheelPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = wheelDelegate
        pan.isEnabled = getTerminal().mouseMode != .off
        addGestureRecognizer(pan)
        wheelPan = pan
    }

    /// Khong goi super: super bat pan "keo chuot" cua SwiftTerm. Cham (tap) van gui su kien chuot binh thuong.
    override func mouseModeChanged(source: Terminal) {
        wheelPan?.isEnabled = source.mouseMode != .off
        if source.mouseMode == .off {
            stopMomentum()
        }
        updateNativeScroll(source)
    }

    override func bufferActivated(source: Terminal) {
        super.bufferActivated(source: source)
        updateNativeScroll(source)
    }

    /// Claude fullscreen (alt screen / bat chuot): tat cuon san co cua UIScrollView. Neu khong, vuot vua gui
    /// con lan cho Claude vua dich khung hinh -> logo Claude hien 2 lan, o nhap luc mat luc hien (ban 2.1).
    /// Dung `source`, khong goi getTerminal(): ham nay co the chay ngay trong super.init.
    private func updateNativeScroll(_ source: Terminal) {
        let appScrolls = source.isCurrentBufferAlternate || source.mouseMode != .off
        isScrollEnabled = !appScrolls
    }

    /// Cho test: cuon san co cua terminal dang bat hay khong
    var isNativeScrollEnabled: Bool {
        isScrollEnabled
    }

    private var stepHeight: CGFloat {
        max(font.lineHeight, 10)
    }

    @objc private func handleWheelPan(_ gesture: UIPanGestureRecognizer) {
        guard getTerminal().mouseMode != .off else { return }
        switch gesture.state {
        case .began:
            stopMomentum()
            accumulated = 0
        case .changed:
            accumulated += gesture.translation(in: self).y
            gesture.setTranslation(.zero, in: self)
            let step = stepHeight
            // Ngon tay keo xuong = xem noi dung cu = lan chuot len
            while accumulated >= step {
                sendWheel(up: true)
                accumulated -= step
            }
            while accumulated <= -step {
                sendWheel(up: false)
                accumulated += step
            }
        case .ended:
            startMomentum(velocity: gesture.velocity(in: self).y)
        case .cancelled, .failed:
            accumulated = 0
        default:
            break
        }
    }

    /// Vuot nhanh thi cuon tiep them vai nhip, cham dan
    private func startMomentum(velocity: CGFloat) {
        var remaining = min(Int(abs(velocity) / (stepHeight * 8)), 40)
        guard remaining > 0 else { return }
        let up = velocity > 0
        var interval: TimeInterval = 0.02
        func tick() {
            guard remaining > 0, getTerminal().mouseMode != .off else { return }
            sendWheel(up: up)
            remaining -= 1
            interval *= 1.08
            let timer = Timer(timeInterval: interval, repeats: false) { _ in tick() }
            RunLoop.main.add(timer, forMode: .common)
            momentumTimer = timer
        }
        tick()
    }

    /// Cho test: pan con lan dang bat hay khong
    var isWheelScrollEnabled: Bool {
        wheelPan?.isEnabled ?? false
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
    }

    private func sendWheel(up: Bool) {
        let terminal = getTerminal()
        let flags = terminal.encodeButton(button: up ? 4 : 5, release: false, shift: false, meta: false, control: false)
        terminal.sendEvent(buttonFlags: flags, x: terminal.cols / 2, y: terminal.rows / 2)
    }
}

/// Cho pan con lan chay cung luc voi cac cu chi san co cua TerminalView (UIScrollView)
private final class SimultaneousGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
