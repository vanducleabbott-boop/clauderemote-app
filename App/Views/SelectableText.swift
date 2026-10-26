//
//  SelectableText.swift
//  ClaudeRemote
//
//  Chu tra loi: UITextView chi doc -> giu de chon vung bat ky roi Sao chep (SwiftUI Text chi copy ca khoi).
//  Link http mo Safari; link file (duong dan trong `code`, file://) goi onOpenFile de tai tu PC.
//

import SwiftUI
import UIKit

struct SelectableText: UIViewRepresentable {
    let text: String
    var markdown: Bool = true
    var fontSize: CGFloat = Markdown.bodySize
    var color: UIColor = Theme.text
    var onOpenFile: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.linkTextAttributes = [.foregroundColor: Theme.accent, .underlineStyle: NSUnderlineStyle.single.rawValue]
        view.delegate = context.coordinator
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.onOpenFile = onOpenFile
        let key = "\(markdown)|\(fontSize)|\(text)"
        // Chu dang chay cap nhat lien tuc: chi dung lai khi noi dung doi
        guard context.coordinator.renderedKey != key else { return }
        context.coordinator.renderedKey = key
        view.attributedText = markdown
            ? Markdown.render(text, size: fontSize, color: color)
            : NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: color])
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width - 32
        guard width > 0, width.isFinite else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(size.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var renderedKey: String?
        var onOpenFile: ((String) -> Void)?

        func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            if let path = Markdown.filePath(from: url) {
                if interaction == .invokeDefaultAction { onOpenFile?(path) }
                return false
            }
            return true
        }
    }
}
