//
//  MessageViews.swift
//  ClaudeRemote
//
//  Cac khoi trong cuoc chat: tin cua ban, chu tra loi, buoc cong cu, xin quyen / cau hoi,
//  file ket qua, thong bao, loi.
//

import SwiftUI

extension Color {
    static let claudeAccent = Color(Theme.accent)
    static let chatBackground = Color(Theme.background)
    static let userBubble = Color(Theme.userBubble)
    static let card = Color(Theme.card)
}

/// Hanh dong tu cac khoi tin nhan (mo file, tra loi quyen)
struct ChatActions {
    var openFile: (String, Int64?) -> Void
    /// Tai file ket qua ve may (co cache), tra ve file tren iPhone
    var fetchFile: (ChatFile) async throws -> URL
    /// Xem file da tai trong app (QuickLook)
    var preview: (URL) -> Void
    var answer: (ChatEvent, PermissionDecision, [String: String]?) -> Void
}

struct EventRow: View {
    let event: ChatEvent
    let tool: String
    let actions: ChatActions

    var body: some View {
        switch event.kind {
        case "user":
            UserMessageView(event: event, actions: actions)
        case "text":
            AssistantTextView(event: event, actions: actions)
        case "tool":
            ToolRowView(event: event, actions: actions)
        case "permission":
            PermissionCard(event: event, tool: tool, actions: actions)
        case "files":
            ResultFilesCard(event: event, actions: actions)
        case "result":
            if event.ok == false {
                Label(event.error ?? "Lỗi", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case "notice":
            Text(event.text ?? "")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        default:
            EmptyView()
        }
    }
}

// MARK: - Tin cua ban

struct UserMessageView: View {
    let event: ChatEvent
    let actions: ChatActions

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let files = event.files, !files.isEmpty {
                FileChips(files: files, actions: actions, alignment: .trailing)
            }
            if let text = event.text, !text.isEmpty {
                SelectableText(text: text, markdown: false)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.userBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
    }
}

// MARK: - Chu tra loi

struct AssistantTextView: View {
    let event: ChatEvent
    let actions: ChatActions
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Markdown.segments(event.text ?? "").enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let t):
                    SelectableText(text: t, onOpenFile: { actions.openFile($0, nil) })
                case .code(let lang, let code):
                    CodeBlockView(language: lang, code: code)
                case .table(let table):
                    TableBlockView(table: table)
                }
            }
            if event.streaming != true, let text = event.text, !text.isEmpty {
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Đã chép" : "Chép", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Đã chép" : "Chép", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.9))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(12)
            }
        }
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.white.opacity(0.08)))
    }
}

/// Bang that: khung o, tieu de dam, o dai tu xuong dong, bang rong cuon ngang, nut Chep (dan vao Excel)
struct TableBlockView: View {
    let table: Markdown.TableData
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: true) {
                TableGrid(table: table)
                    .padding(.bottom, 2)
            }

            Button {
                UIPasteboard.general.string = table.tsv
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Label(copied ? "Đã chép bảng" : "Chép bảng", systemImage: copied ? "checkmark" : "tablecells")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

struct TableGrid: View {
    let table: Markdown.TableData
    private static let maxCellWidth: CGFloat = 240

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(0..<table.columnCount, id: \.self) { c in
                            cell(c < table.header.count ? table.header[c] : "", column: c, header: true)
                        }
                    }
                    .background(Color.white.opacity(0.08))
                    ForEach(Array(table.rows.enumerated()), id: \.offset) { r, row in
                        GridRow {
                            ForEach(0..<table.columnCount, id: \.self) { c in
                                cell(c < row.count ? row[c] : "", column: c, header: false)
                            }
                        }
                        .background(r % 2 == 1 ? Color.white.opacity(0.03) : Color.clear)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.15)))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cell(_ text: String, column: Int, header: Bool) -> some View {
        let align = column < table.aligns.count ? table.aligns[column] : .leading
        let frameAlign: Alignment = align == .center ? .top : align == .trailing ? .topTrailing : .topLeading
        let textAlign: TextAlignment = align == .center ? .center : align == .trailing ? .trailing : .leading
        return Text(Markdown.cellAttributed(text, bold: header))
            .font(.system(size: 14))
            .foregroundColor(.primary)
            .multilineTextAlignment(textAlign)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: Self.maxCellWidth, alignment: frameAlign)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlign)
            .overlay(alignment: .trailing) {
                if column < table.columnCount - 1 {
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                }
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            }
            .textSelection(.enabled)
    }
}

// MARK: - Buoc cong cu

struct ToolRowView: View {
    let event: ChatEvent
    let actions: ChatActions
    @State private var expanded = false

    private var icon: String {
        switch event.name {
        case "Read", "read_file", "view_file": return "doc.text"
        case "Write", "write_file", "write_to_file": return "doc.badge.plus"
        case "Edit", "MultiEdit", "NotebookEdit", "replace_file_content", "multi_replace_file_content", "edit_file": return "pencil"
        case "Bash", "PowerShell", "run_command": return "terminal"
        case "Glob", "Grep", "find_by_name", "grep_search": return "magnifyingglass"
        case "WebFetch", "WebSearch", "read_url_content", "search_web": return "globe"
        case "Task", "Agent", "invoke_subagent": return "person.2"
        case "TodoWrite": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }

    private var canOpen: Bool {
        guard event.path != nil, event.status == "done" else { return false }
        return ["Write", "Edit", "MultiEdit", "write_file", "write_to_file", "replace_file_content", "multi_replace_file_content", "edit_file", "Read", "read_file", "view_file"].contains(event.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 18)
                Text(event.title ?? event.name ?? "")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if canOpen, let path = event.path {
                    Button("Mở") { actions.openFile(path, nil) }
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.claudeAccent)
                        .buttonStyle(.plain)
                }
                statusIcon
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if event.output?.isEmpty == false { expanded.toggle() }
            }

            if expanded, let output = event.output {
                SelectableText(text: output, markdown: false, fontSize: 12, color: Theme.secondaryText)
                    .padding(10)
                    .background(Color.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch event.status {
        case "running":
            ProgressView().scaleEffect(0.7)
        case "error":
            Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.red)
        default:
            if event.output?.isEmpty == false {
                Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2).foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Xin quyen / cau hoi

struct PermissionCard: View {
    let event: ChatEvent
    let tool: String
    let actions: ChatActions
    @State private var selections: [String: Set<String>] = [:]

    private var pending: Bool { event.status == "pending" }
    private var toolName: String { tool == "agy" ? "agy" : "Claude" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let questions = event.questions, !questions.isEmpty {
                questionsView(questions)
            } else if event.tool == "ExitPlanMode" {
                Label("Kế hoạch của \(toolName)", systemImage: "list.bullet.clipboard")
                    .font(.subheadline.weight(.semibold))
                if let plan = event.detail {
                    SelectableText(text: plan, onOpenFile: { actions.openFile($0, nil) })
                }
                if pending {
                    HStack {
                        actionButton("Làm theo kế hoạch", prominent: true) { actions.answer(event, .allow, nil) }
                        actionButton("Chưa, lập tiếp", prominent: false) { actions.answer(event, .deny, nil) }
                    }
                }
            } else {
                Label("\(toolName) muốn \((event.title ?? "dùng công cụ").lowercased())", systemImage: "hand.raised.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(pending ? .claudeAccent : .secondary)
                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(pending ? 12 : 2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .textSelection(.enabled)
                }
                if pending {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            actionButton("Cho phép", prominent: true) { actions.answer(event, .allow, nil) }
                            actionButton("Từ chối", prominent: false) { actions.answer(event, .deny, nil) }
                        }
                        actionButton("Luôn cho phép trong phiên này", prominent: false) { actions.answer(event, .always, nil) }
                    }
                }
            }
            if !pending {
                statusLabel
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(pending ? Color.claudeAccent.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var statusLabel: some View {
        let (text, icon, color): (String, String, Color) = {
            switch event.status {
            case "allowed": return ("Đã cho phép", "checkmark.circle.fill", .green)
            case "denied": return ("Đã từ chối", "xmark.circle.fill", .red)
            default: return ("Hết hiệu lực", "clock", .secondary)
            }
        }()
        return Label(text, systemImage: icon)
            .font(.caption)
            .foregroundColor(color)
    }

    @ViewBuilder
    private func questionsView(_ questions: [ChatQuestion]) -> some View {
        ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
            VStack(alignment: .leading, spacing: 8) {
                Text(q.question)
                    .font(.subheadline.weight(.semibold))
                if pending {
                    ForEach(q.options, id: \.label) { opt in
                        let chosen = selections[q.question]?.contains(opt.label) == true
                        Button {
                            toggle(q, opt.label, in: questions)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: (q.multiSelect == true)
                                      ? (chosen ? "checkmark.square.fill" : "square")
                                      : (chosen ? "largecircle.fill.circle" : "circle"))
                                    .foregroundColor(chosen ? .claudeAccent : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(opt.label).foregroundColor(.primary)
                                    if let d = opt.description, !d.isEmpty, d != opt.label {
                                        Text(d).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Color.black.opacity(chosen ? 0.35 : 0.2))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                } else if let answer = event.answers?[q.question] {
                    Label(answer, systemImage: "arrowshape.turn.up.right.fill")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
        }
        if pending {
            let ready = questions.allSatisfy { selections[$0.question]?.isEmpty == false }
            HStack(spacing: 8) {
                actionButton("Gửi trả lời", prominent: true) {
                    var answers: [String: String] = [:]
                    for q in questions {
                        let picked = q.options.map(\.label).filter { selections[q.question]?.contains($0) == true }
                        answers[q.question] = picked.joined(separator: ", ")
                    }
                    actions.answer(event, .allow, answers)
                }
                .disabled(!ready)
                .opacity(ready ? 1 : 0.5)
                actionButton("Bỏ qua", prominent: false) { actions.answer(event, .deny, nil) }
            }
        }
    }

    private func toggle(_ q: ChatQuestion, _ label: String, in questions: [ChatQuestion]) {
        var set = selections[q.question] ?? []
        if q.multiSelect == true {
            if set.contains(label) { set.remove(label) } else { set.insert(label) }
        } else {
            set = [label]
        }
        selections[q.question] = set
        // 1 cau hoi chon 1: bam la gui luon
        if questions.count == 1, q.multiSelect != true {
            actions.answer(event, .allow, [q.question: label])
        }
    }

    private func actionButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundColor(prominent ? .white : .primary)
                .background(prominent ? Color.claudeAccent : Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - File

struct ResultFilesCard: View {
    let event: ChatEvent
    let actions: ChatActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("File kết quả", systemImage: "folder.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.green)
            let files = event.files ?? []
            ForEach(files) { f in
                DocumentCard(file: f, actions: actions, large: files.count <= 3)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct FileChips: View {
    let files: [ChatFile]
    let actions: ChatActions
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            ForEach(files) { f in
                Button {
                    if let path = f.path { actions.openFile(path, f.size) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: FileIcon.name(for: f.name))
                            .foregroundColor(.claudeAccent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(f.name)
                                .font(.footnote)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let size = f.size {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(f.path == nil)
            }
        }
    }
}

enum FileIcon {
    static func kind(for file: String) -> String {
        switch (file as NSString).pathExtension.lowercased() {
        case "pdf": return "PDF"
        case "doc", "docx": return "Word"
        case "xls", "xlsx", "xlsm": return "Excel"
        case "csv": return "CSV"
        case "ppt", "pptx": return "PowerPoint"
        case "txt", "md", "rtf": return "Văn bản"
        default: return (file as NSString).pathExtension.uppercased()
        }
    }

    static func color(for file: String) -> Color {
        switch (file as NSString).pathExtension.lowercased() {
        case "pdf": return Color(red: 0.86, green: 0.25, blue: 0.22)
        case "doc", "docx": return Color(red: 0.17, green: 0.42, blue: 0.82)
        case "xls", "xlsx", "xlsm", "csv": return Color(red: 0.13, green: 0.55, blue: 0.32)
        case "ppt", "pptx": return Color(red: 0.85, green: 0.42, blue: 0.18)
        default: return .claudeAccent
        }
    }

    static func name(for file: String) -> String {
        switch (file as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp": return "photo"
        case "pdf": return "doc.richtext"
        case "doc", "docx", "txt", "md", "rtf": return "doc.text"
        case "xls", "xlsx", "csv": return "tablecells"
        case "ppt", "pptx": return "rectangle.on.rectangle"
        case "zip", "rar", "7z": return "doc.zipper"
        case "mp4", "mov": return "film"
        case "mp3", "m4a", "wav": return "waveform"
        default: return "doc"
        }
    }
}
