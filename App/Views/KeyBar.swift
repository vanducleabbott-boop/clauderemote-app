//
//  KeyBar.swift
//  ClaudeRemote
//
//  Thanh phim phu (inputAccessoryView) tren ban phim iOS de gui cac phim dieu khien terminal.
//
//  Cham / giu:
//  - Ctrl, Alt: cham = ap dung cho 1 phim tiep theo (ca phim go tren ban phim); giu = khoa
//  - Esc: giu = Esc Esc (quay lai / sua tin truoc trong Claude)
//  - ⏎: giu = xuong dong khong gui (Alt+Enter)
//  - Mui ten, PgUp/PgDn: giu = lap lai lien tuc
//  - "Phím tắt": menu cac to hop cua Claude / agy
//

import UIKit
import SwiftTerm

final class KeyBar: UIView {
    private weak var terminalView: TerminalView?
    private weak var connection: TerminalConnection?
    private let modifiers: KeyModifiers
    private let tool: String

    private var ctrlButton: UIButton?
    private var altButton: UIButton?
    private var repeatTimer: Timer?

    private static let normalColor = UIColor(white: 0.22, alpha: 1)
    private static let onceColor = UIColor.systemBlue
    private static let lockedColor = UIColor.systemOrange

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    init(terminalView: TerminalView, connection: TerminalConnection, modifiers: KeyModifiers, tool: String) {
        self.terminalView = terminalView
        self.connection = connection
        self.modifiers = modifiers
        self.tool = tool
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        self.autoresizingMask = .flexibleWidth
        self.backgroundColor = UIColor(white: 0.12, alpha: 1)
        setupViews()
        modifiers.onChange = { [weak self] in
            self?.refreshModifierButtons()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        repeatTimer?.invalidate()
    }

    // MARK: - Layout

    private func setupViews() {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.delaysContentTouches = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 6
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -6),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -6),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -12)
        ])

        // Ctrl / Alt: cham = 1 lan, giu = khoa
        let ctrl = makeButton("Ctrl", tap: { [weak self] in self?.modifiers.tapCtrl() },
                              hold: { [weak self] in self?.modifiers.lockCtrl() })
        let alt = makeButton("Alt", tap: { [weak self] in self?.modifiers.tapAlt() },
                             hold: { [weak self] in self?.modifiers.lockAlt() })
        ctrlButton = ctrl
        altButton = alt

        let buttons: [UIButton] = [
            ctrl,
            alt,
            makeButton("Esc", tap: { [weak self] in self?.send([0x1B]) },
                       hold: { [weak self] in self?.send([0x1B, 0x1B]) }),
            makeButton("^C", tap: { [weak self] in self?.send([0x03]) }),
            makeButton("Tab", tap: { [weak self] in self?.send([0x09]) }),
            makeButton("⇧Tab", tap: { [weak self] in self?.send([0x1B, 0x5B, 0x5A]) }),
            makeRepeatButton("↑") { [weak self] in self?.sendSpecial(.up) },
            makeRepeatButton("↓") { [weak self] in self?.sendSpecial(.down) },
            makeRepeatButton("←") { [weak self] in self?.sendSpecial(.left) },
            makeRepeatButton("→") { [weak self] in self?.sendSpecial(.right) },
            makeButton("⏎", tap: { [weak self] in self?.sendEnter() },
                       hold: { [weak self] in self?.send([0x1B, 0x0D]) }),
            makeShortcutsButton(),
            makeButton("/", tap: { [weak self] in self?.sendTyped("/") }),
            makeButton("@", tap: { [weak self] in self?.sendTyped("@") }),
            makeButton("!", tap: { [weak self] in self?.sendTyped("!") }),
            makeRepeatButton("PgUp") { [weak self] in self?.sendSpecial(.pageUp) },
            makeRepeatButton("PgDn") { [weak self] in self?.sendSpecial(.pageDown) },
            makeButton("Home", tap: { [weak self] in self?.sendSpecial(.home) }),
            makeButton("End", tap: { [weak self] in self?.sendSpecial(.end) })
        ]
        buttons.forEach { stackView.addArrangedSubview($0) }
        refreshModifierButtons()
    }

    private func styledButton(_ title: String) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attrs in
            var a = attrs
            a.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            return a
        }
        config.baseForegroundColor = .white
        let button = UIButton(configuration: config)
        button.backgroundColor = Self.normalColor
        button.layer.cornerRadius = 6
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        return button
    }

    /// Nut cham + (tuy chon) giu 0.4s cho thao tac khac
    private func makeButton(_ title: String, tap: @escaping () -> Void, hold: (() -> Void)? = nil) -> UIButton {
        let button = styledButton(title)
        button.addAction(UIAction { _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            tap()
        }, for: .touchUpInside)

        if let hold = hold {
            let press = ClosureLongPress(minimumDuration: 0.4) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                hold()
            }
            button.addGestureRecognizer(press.recognizer)
            objc_setAssociatedObject(button, &Self.pressKey, press, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        return button
    }

    /// Nut giu de lap lai (mui ten, PgUp/PgDn): gui ngay khi cham, giu 0.4s thi lap moi 0.07s
    private func makeRepeatButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = styledButton(title)
        button.addAction(UIAction { [weak self] _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
            self?.repeatTimer?.invalidate()
            let start = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
                let timer = Timer(timeInterval: 0.07, repeats: true) { _ in action() }
                RunLoop.main.add(timer, forMode: .common)
                self?.repeatTimer = timer
            }
            RunLoop.main.add(start, forMode: .common)
            self?.repeatTimer = start
        }, for: .touchDown)
        let stop = UIAction { [weak self] _ in
            self?.repeatTimer?.invalidate()
            self?.repeatTimer = nil
        }
        button.addAction(stop, for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])
        return button
    }

    // MARK: - Menu phim tat Claude / agy

    private func makeShortcutsButton() -> UIButton {
        let button = styledButton("Phím tắt")
        button.backgroundColor = UIColor(white: 0.3, alpha: 1)
        button.menu = buildShortcutsMenu()
        button.showsMenuAsPrimaryAction = true
        return button
    }

    private func item(_ title: String, _ keys: String, _ bytes: [UInt8], destructive: Bool = false) -> UIAction {
        UIAction(title: title, subtitle: keys, attributes: destructive ? [.destructive] : []) { [weak self] _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.send(bytes)
        }
    }

    private func buildShortcutsMenu() -> UIMenu {
        let isAgy = tool.lowercased() == "agy"

        let common = UIMenu(title: "", options: .displayInline, children: [
            item("Mở rộng / thu gọn chi tiết", "Ctrl+O", [0x0F]),
            item("Đưa tác vụ chạy nền", "Ctrl+B", [0x02]),
            item("Quay lại / sửa tin trước", "Esc Esc", [0x1B, 0x1B]),
            item("Xuống dòng (không gửi)", "Alt+Enter", [0x1B, 0x0D])
        ])

        let toolMenu: UIMenu
        if isAgy {
            toolMenu = UIMenu(title: "agy", options: .displayInline, children: [
                item("Xem artifacts chờ duyệt", "Ctrl+R", [0x12]),
                item("Đổi chế độ", "Shift+Tab", [0x1B, 0x5B, 0x5A])
            ])
        } else {
            toolMenu = UIMenu(title: "Claude", options: .displayInline, children: [
                item("Tìm lại lệnh đã gõ", "Ctrl+R", [0x12]),
                item("Hiện / ẩn danh sách việc", "Ctrl+T", [0x14]),
                item("Chọn model", "Alt+P", [0x1B, 0x70]),
                item("Bật / tắt suy nghĩ (thinking)", "Alt+T", [0x1B, 0x74]),
                item("Chế độ nhanh (fast)", "Alt+O", [0x1B, 0x6F]),
                item("Xoá ô nhập", "Ctrl+L", [0x0C]),
                item("Cất tạm ô nhập (stash)", "Ctrl+S", [0x13]),
                item("Đổi chế độ quyền", "Shift+Tab", [0x1B, 0x5B, 0x5A])
            ])
        }

        let scroll = UIMenu(title: "Cuộn", options: .displayInline, children: [
            item("Lên đầu cuộc trò chuyện", "Ctrl+Home", [0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x48]),
            item("Xuống cuối", "Ctrl+End", [0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x46])
        ])

        let danger = UIMenu(title: "", options: .displayInline, children: [
            item("Thoát phiên", "Ctrl+D", [0x04], destructive: true)
        ])

        return UIMenu(title: isAgy ? "Phím tắt agy" : "Phím tắt Claude", children: [common, toolMenu, scroll, danger])
    }

    // MARK: - Gui

    private func refreshModifierButtons() {
        func color(_ state: KeyModifiers.State) -> UIColor {
            switch state {
            case .off: return Self.normalColor
            case .once: return Self.onceColor
            case .locked: return Self.lockedColor
            }
        }
        ctrlButton?.backgroundColor = color(modifiers.ctrl)
        altButton?.backgroundColor = color(modifiers.alt)
        ctrlButton?.configuration?.title = modifiers.ctrl == .locked ? "Ctrl 🔒" : "Ctrl"
        altButton?.configuration?.title = modifiers.alt == .locked ? "Alt 🔒" : "Alt"
    }

    private func send(_ bytes: [UInt8]) {
        connection?.send(bytes: Data(bytes))
    }

    /// Ky tu thuong tu thanh phim: van ap dung Ctrl/Alt neu dang bat
    private func sendTyped(_ text: String) {
        connection?.send(bytes: modifiers.apply(toTyped: Data(text.utf8)))
    }

    private func sendSpecial(_ key: SpecialKey) {
        let appCursor = terminalView?.getTerminal().applicationCursor ?? false
        send(modifiers.apply(toSpecial: key, applicationCursor: appCursor))
    }

    private func sendEnter() {
        send(modifiers.applyToEnter())
    }

    private static var pressKey: UInt8 = 0
}

/// UILongPressGestureRecognizer goi closure 1 lan khi bat dau giu
private final class ClosureLongPress: NSObject {
    let recognizer: UILongPressGestureRecognizer
    private let action: () -> Void

    init(minimumDuration: TimeInterval, action: @escaping () -> Void) {
        self.action = action
        self.recognizer = UILongPressGestureRecognizer()
        super.init()
        recognizer.minimumPressDuration = minimumDuration
        recognizer.addTarget(self, action: #selector(handle(_:)))
    }

    @objc private func handle(_ g: UILongPressGestureRecognizer) {
        if g.state == .began {
            action()
        }
    }
}
