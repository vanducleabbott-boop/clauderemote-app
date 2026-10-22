//
//  KeyBar.swift
//  ClaudeRemote
//
//  Thanh phim phu (inputAccessoryView) tren ban phim iOS de gui cac phim dieu khien terminal.
//

import UIKit
import SwiftTerm

final class KeyBar: UIView {
    private weak var terminalView: TerminalView?
    private weak var connection: TerminalConnection?

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    init(terminalView: TerminalView, connection: TerminalConnection) {
        self.terminalView = terminalView
        self.connection = connection
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 44))
        self.autoresizingMask = .flexibleWidth
        self.backgroundColor = UIColor(white: 0.12, alpha: 1)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func make(terminalView: TerminalView, connection: TerminalConnection) -> UIView {
        return KeyBar(terminalView: terminalView, connection: connection)
    }

    private func setupViews() {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
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

        let buttons: [(String, () -> Void)] = [
            ("Esc", { [weak self] in self?.sendBytes([0x1B]) }),
            ("Tab", { [weak self] in self?.sendBytes([0x09]) }),
            ("⇧Tab", { [weak self] in self?.sendBytes([0x1B, 0x5B, 0x5A]) }),
            ("^C", { [weak self] in self?.sendBytes([0x03]) }),
            ("^D", { [weak self] in self?.sendBytes([0x04]) }),
            ("↑", { [weak self] in self?.sendArrow(code: 0x41) }),
            ("↓", { [weak self] in self?.sendArrow(code: 0x42) }),
            ("←", { [weak self] in self?.sendArrow(code: 0x44) }),
            ("→", { [weak self] in self?.sendArrow(code: 0x43) }),
            ("⏎", { [weak self] in self?.sendBytes([0x0D]) })
        ]

        for (title, handler) in buttons {
            let action = UIAction { _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                handler()
            }
            let button = UIButton(primaryAction: action)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
            button.setTitleColor(.white, for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor(white: 0.22, alpha: 1)
            button.layer.cornerRadius = 6
            button.clipsToBounds = true
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            stackView.addArrangedSubview(button)
        }
    }

    private func sendBytes(_ bytes: [UInt8]) {
        connection?.send(bytes: Data(bytes))
    }

    private func sendArrow(code: UInt8) {
        let appCursor = terminalView?.getTerminal().applicationCursor ?? false
        let prefix: UInt8 = appCursor ? 0x4F : 0x5B
        connection?.send(bytes: Data([0x1B, prefix, code]))
    }
}
