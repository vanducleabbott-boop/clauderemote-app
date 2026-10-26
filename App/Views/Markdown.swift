//
//  Markdown.swift
//  ClaudeRemote
//
//  Doi markdown cua Claude/agy -> NSAttributedString cho UITextView (chon vung + copy duoc).
//  Ho tro: tieu de, danh sach, trich dan, khoi code, bang (giu nguyen dang chu deu), duong ke,
//  dam / nghieng / code / gach / link. Duong dan file trong `code` hoac link file:// -> bam mo file.
//

import UIKit
import SwiftUI

enum Theme {
    static let accent = UIColor(red: 0.85, green: 0.47, blue: 0.34, alpha: 1)      // cam Claude
    static let background = UIColor(red: 0.12, green: 0.118, blue: 0.11, alpha: 1)
    static let userBubble = UIColor(red: 0.19, green: 0.185, blue: 0.175, alpha: 1)
    static let card = UIColor(red: 0.16, green: 0.155, blue: 0.145, alpha: 1)
    static let codeBackground = UIColor(white: 1, alpha: 0.07)
    static let text = UIColor(white: 0.93, alpha: 1)
    static let secondaryText = UIColor(white: 0.62, alpha: 1)
}

enum Markdown {
    /// Link noi bo de mo file tren PC: crfile://open?path=<duong dan>
    static let fileScheme = "crfile"

    static func fileLink(_ path: String) -> URL? {
        var c = URLComponents()
        c.scheme = fileScheme
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "path", value: path)]
        return c.url
    }

    static func filePath(from url: URL) -> String? {
        if url.scheme == fileScheme {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value
        }
        if url.isFileURL {
            return url.path
        }
        return nil
    }

    // Duong dan file: co / hoac \ va phan mo rong (C:\a\b.docx, src/app.js, /Users/x/y.txt)
    private static let pathRegex = try! NSRegularExpression(
        pattern: #"^(?:[A-Za-z]:[\\/]|[~./\\]|[\w\-. ]+[\\/])[^\s"'<>|*?]*\.[A-Za-z0-9]{1,8}$"#
    )

    static func looksLikePath(_ s: String) -> Bool {
        guard s.count <= 400, s.contains("/") || s.contains("\\") else { return false }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return false }
        return pathRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static let bodySize: CGFloat = 16

    enum Segment: Equatable {
        case text(String)
        case code(language: String, code: String)
        case table(TableData)
    }

    struct TableData: Equatable {
        enum Align: Equatable { case leading, center, trailing }
        var header: [String]
        var rows: [[String]]
        var aligns: [Align]

        var columnCount: Int { max(header.count, rows.map(\.count).max() ?? 0) }

        /// Chep: tab giua cot, xuong dong giua hang -> dan vao Excel / Google Sheets giu dung cot
        var tsv: String {
            ([header] + rows).map { row in
                row.map { Markdown.plainCell($0) }.joined(separator: "\t")
            }.joined(separator: "\n")
        }
    }

    /// Tach khoi ``` va bang markdown ra rieng (hien thanh the co nen / bang that, cuon ngang);
    /// khoi code chua dong (dang viet) van la code
    static func segments(_ text: String) -> [Segment] {
        var out: [Segment] = []
        var buffer: [String] = []
        func flushText() {
            let t = buffer.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !t.isEmpty { out.append(.text(t)) }
            buffer = []
        }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flushText()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                out.append(.code(language: lang, code: code.joined(separator: "\n")))
                i += 1
                continue
            }
            // Bang: dong "| a | b |" ngay sau la dong phan cach "|---|:--:|"
            if trimmed.hasPrefix("|"), i + 1 < lines.count, let aligns = separatorAligns(lines[i + 1]) {
                flushText()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("|") else { break }
                    rows.append(tableCells(t))
                    i += 1
                }
                out.append(.table(TableData(header: header, rows: rows, aligns: aligns)))
                continue
            }
            buffer.append(line)
            i += 1
        }
        flushText()
        return out
    }

    /// "| a | b \\| c |" -> ["a", "b | c"]
    static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") && !t.hasSuffix("\\|") { t.removeLast() }
        var cells: [String] = []
        var cur = ""
        var escape = false
        for ch in t {
            if escape { cur.append(ch); escape = false; continue }
            if ch == "\\" { escape = true; continue }
            if ch == "|" { cells.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""; continue }
            cur.append(ch)
        }
        cells.append(cur.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func separatorAligns(_ line: String) -> [TableData.Align]? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") || t.contains(":") else { return nil }
        let cells = tableCells(t)
        var aligns: [TableData.Align] = []
        for c in cells {
            guard !c.isEmpty, c.allSatisfy({ "-: ".contains($0) }), c.contains("-") else { return nil }
            let left = c.hasPrefix(":"), right = c.hasSuffix(":")
            aligns.append(left && right ? .center : right ? .trailing : .leading)
        }
        return aligns
    }

    /// Bo ky hieu markdown trong o bang (khi chep)
    static func plainCell(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        for mark in ["**", "__", "`", "~~"] { t = t.replacingOccurrences(of: mark, with: "") }
        return t.replacingOccurrences(of: "<br>", with: " ")
    }

    /// O bang: markdown trong dong -> AttributedString cho SwiftUI Text; <br> -> xuong dong
    static func cellAttributed(_ s: String, bold: Bool) -> AttributedString {
        let src = s.replacingOccurrences(of: "<br>", with: "\n").replacingOccurrences(of: "<br/>", with: "\n")
        var a = (try? AttributedString(
            markdown: src,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        )) ?? AttributedString(src)
        for run in a.runs {
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                a[run.range].font = .system(size: 13, design: .monospaced)
                a[run.range].backgroundColor = Color.white.opacity(0.08)
            }
            if run.link != nil {
                a[run.range].foregroundColor = Color(Theme.accent)
            }
        }
        if bold {
            a.font = .system(size: 14, weight: .semibold)
        }
        return a
    }

    static func render(_ text: String, size: CGFloat = bodySize, color: UIColor = Theme.text) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var i = 0
        var first = true

        func newline() {
            if !first { out.append(NSAttributedString(string: "\n")) }
            first = false
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Khoi code ```
            if trimmed.hasPrefix("```") {
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1
                newline()
                out.append(codeBlock(code.joined(separator: "\n"), size: size))
                continue
            }

            // Bang |a|b|: giu dang chu deu de cot thang hang
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1 {
                var rows: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix("|") else { break }
                    if !t.replacingOccurrences(of: "|", with: "").allSatisfy({ "-: ".contains($0) }) {
                        rows.append(t)
                    }
                    i += 1
                }
                newline()
                out.append(table(rows, size: size))
                continue
            }

            newline()
            if trimmed.isEmpty {
                out.append(NSAttributedString(string: "", attributes: [.font: UIFont.systemFont(ofSize: size * 0.5)]))
            } else if let h = heading(trimmed) {
                let font = UIFont.systemFont(ofSize: size + CGFloat(max(0, 4 - h.level)) * 1.5 + 1, weight: .bold)
                out.append(inline(h.text, font: font, color: color, paragraph: paragraphStyle(spacingBefore: 6)))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                out.append(NSAttributedString(string: "────────────", attributes: [.foregroundColor: Theme.secondaryText, .font: UIFont.systemFont(ofSize: size)]))
            } else if let item = listItem(line) {
                let indent = CGFloat(item.level) * 16
                let ps = paragraphStyle(headIndent: indent + 20, firstLineIndent: indent)
                let marker = NSMutableAttributedString(string: item.marker + "\t", attributes: [
                    .font: UIFont.systemFont(ofSize: size), .foregroundColor: Theme.secondaryText, .paragraphStyle: ps
                ])
                marker.append(inline(item.text, font: .systemFont(ofSize: size), color: color, paragraph: ps))
                out.append(marker)
            } else if trimmed.hasPrefix(">") {
                let body = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
                let ps = paragraphStyle(headIndent: 14, firstLineIndent: 0)
                let bar = NSMutableAttributedString(string: "▎ ", attributes: [.foregroundColor: Theme.secondaryText, .font: UIFont.systemFont(ofSize: size), .paragraphStyle: ps])
                bar.append(inline(body, font: .italicSystemFont(ofSize: size), color: Theme.secondaryText, paragraph: ps))
                out.append(bar)
            } else {
                out.append(inline(line, font: .systemFont(ofSize: size), color: color, paragraph: paragraphStyle()))
            }
            i += 1
        }
        return out
    }

    // MARK: - Khoi

    private static func paragraphStyle(headIndent: CGFloat = 0, firstLineIndent: CGFloat = 0, spacingBefore: CGFloat = 0) -> NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 2
        ps.paragraphSpacing = 4
        ps.paragraphSpacingBefore = spacingBefore
        ps.headIndent = headIndent
        ps.firstLineHeadIndent = firstLineIndent
        ps.tabStops = [NSTextTab(textAlignment: .left, location: headIndent)]
        ps.defaultTabInterval = 20
        return ps
    }

    private static func heading(_ s: String) -> (level: Int, text: String)? {
        guard s.hasPrefix("#") else { return nil }
        let level = s.prefix(while: { $0 == "#" }).count
        guard level <= 6 else { return nil }
        let rest = s.dropFirst(level)
        guard rest.first == " " else { return nil }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    private static func listItem(_ line: String) -> (level: Int, marker: String, text: String)? {
        let spaces = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let rest = line.dropFirst(spaces)
        let level = min(spaces / 2, 4)
        if let f = rest.first, "-*+".contains(f), rest.dropFirst().first == " " {
            var text = String(rest.dropFirst(2))
            var marker = "•"
            if text.hasPrefix("[ ] ") { marker = "☐"; text = String(text.dropFirst(4)) }
            else if text.lowercased().hasPrefix("[x] ") { marker = "☑"; text = String(text.dropFirst(4)) }
            return (level, marker, text)
        }
        let digits = rest.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 3 {
            let after = rest.dropFirst(digits.count)
            if let p = after.first, p == "." || p == ")", after.dropFirst().first == " " {
                return (level, digits + ".", String(after.dropFirst(2)))
            }
        }
        return nil
    }

    private static func codeBlock(_ code: String, size: CGFloat) -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = 1
        ps.paragraphSpacing = 6
        ps.paragraphSpacingBefore = 4
        return NSAttributedString(string: code, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: size - 3, weight: .regular),
            .foregroundColor: Theme.text,
            .backgroundColor: Theme.codeBackground,
            .paragraphStyle: ps
        ])
    }

    private static func table(_ rows: [String], size: CGFloat) -> NSAttributedString {
        let cells = rows.map { row -> [String] in
            row.trimmingCharacters(in: CharacterSet(charactersIn: "| ")).components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            }
        }
        let cols = cells.map(\.count).max() ?? 0
        var widths = Array(repeating: 0, count: cols)
        for r in cells {
            for (j, c) in r.enumerated() { widths[j] = min(max(widths[j], c.count), 28) }
        }
        let text = cells.enumerated().map { (ri, r) -> String in
            let line = (0..<cols).map { j -> String in
                let c = j < r.count ? r[j] : ""
                let cut = c.count > 28 ? String(c.prefix(27)) + "…" : c
                return cut + String(repeating: " ", count: max(0, widths[j] - cut.count))
            }.joined(separator: " │ ")
            if ri == 0 && cells.count > 1 {
                return line + "\n" + widths.map { String(repeating: "─", count: $0) }.joined(separator: "─┼─")
            }
            return line
        }.joined(separator: "\n")
        let ps = NSMutableParagraphStyle()
        ps.paragraphSpacing = 4
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.monospacedSystemFont(ofSize: size - 4, weight: .regular),
            .foregroundColor: Theme.text,
            .paragraphStyle: ps
        ])
    }

    // MARK: - Trong dong

    static func inline(_ s: String, font: UIFont, color: UIColor, paragraph: NSParagraphStyle) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        guard let parsed = try? AttributedString(
            markdown: s,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        ) else {
            return NSAttributedString(string: s, attributes: base)
        }
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let piece = String(parsed[run.range].characters)
            var attrs = base
            let intent = run.inlinePresentationIntent ?? []
            var traits: UIFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            if intent.contains(.code) {
                attrs[.font] = UIFont.monospacedSystemFont(ofSize: font.pointSize - 1.5, weight: traits.contains(.traitBold) ? .bold : .regular)
                attrs[.backgroundColor] = Theme.codeBackground
                if looksLikePath(piece), let url = fileLink(piece) {
                    attrs[.link] = url
                }
            } else if !traits.isEmpty {
                let combined = font.fontDescriptor.symbolicTraits.union(traits)
                if let d = font.fontDescriptor.withSymbolicTraits(combined) {
                    attrs[.font] = UIFont(descriptor: d, size: font.pointSize)
                }
            }
            if intent.contains(.strikethrough) {
                attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            if let link = run.link {
                if let path = filePath(from: link), let url = fileLink(path) {
                    attrs[.link] = url
                } else {
                    attrs[.link] = link
                }
            }
            out.append(NSAttributedString(string: piece, attributes: attrs))
        }
        return out
    }
}
