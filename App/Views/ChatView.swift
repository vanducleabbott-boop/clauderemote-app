//
//  ChatView.swift
//  ClaudeRemote
//
//  Man hinh chat: tin nhan + cau tra loi, go xong bam Gui moi chay tren PC.
//  Dinh kem anh/file (gui len thu muc File xu ly cua phien), mo file ket qua bang QuickLook
//  (co nut chia se / mo bang app khac). Che do quyen chon o goc duoi ben trai nhu tren PC.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import QuickLook

struct ChatView: View {
    @StateObject private var session: ChatSession
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ChatStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft = ""
    @State private var attachments: [PickedFile] = []
    @State private var sending = false
    @State private var progress: String?
    @State private var errorText: String?
    @State private var atBottom = true
    @State private var busySince: Date?
    @State private var previewURL: URL?
    @State private var downloading = false
    @State private var showPhotos = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showImporter = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var commands: [SlashCommand] = []
    @FocusState private var inputFocused: Bool

    init(meta: ChatMeta, api: ServerAPI) {
        _session = StateObject(wrappedValue: ChatSession(meta: meta, api: api))
    }

    private var meta: ChatMeta { session.meta }
    private var api: ServerAPI { settings.makeAPI() }

    var body: some View {
        VStack(spacing: 0) {
            messages
            composer
        }
        .background(Color.chatBackground.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(meta.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle()
                            .fill(session.connected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text("\(meta.toolName) · \(Self.folderName(meta.cwd))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        newName = meta.name
                        renaming = true
                    } label: {
                        Label("Đổi tên", systemImage: "pencil")
                    }
                    Button {
                        UIPasteboard.general.string = meta.cwd
                    } label: {
                        Label("Chép đường dẫn thư mục", systemImage: "folder")
                    }
                    Section(meta.cwd) {}
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Đổi tên", isPresented: $renaming) {
            TextField("Tên", text: $newName)
            Button("Huỷ", role: .cancel) {}
            Button("Lưu") { rename() }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photoItems, maxSelectionCount: 20, matching: .images)
        .onChange(of: photoItems) { items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task { await addPhotos(items) }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): addImported(urls)
            case .failure(let err): errorText = err.localizedDescription
            }
        }
        .quickLookPreview($previewURL)
        .overlay {
            if downloading {
                ProgressView("Đang tải file…")
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear {
            session.start()
            if meta.isBusy { busySince = Date() }
        }
        .task {
            #if DEBUG
            // Thu tren may ao: -draft "/co" dien san o nhap
            if let d = UserDefaults.standard.string(forKey: "draft"), draft.isEmpty { draft = d }
            #endif
            await loadCommands()
        }
        .onChange(of: draft) { text in
            // Moi lan bat dau go "/" thi lay lai (ky nang moi co sau tin dau tien cua phien)
            if text == "/" { Task { await loadCommands() } }
        }
        .onDisappear {
            session.stop()
            store.upsert(session.meta)
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { session.ensureConnected() }
        }
        .onChange(of: meta.status) { status in
            if status == "idle" { busySince = nil } else if busySince == nil { busySince = Date() }
        }
    }

    // MARK: - Danh sach tin

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if session.events.isEmpty {
                        emptyState
                    }
                    ForEach(session.events) { event in
                        EventRow(event: event, tool: meta.tool, actions: actions)
                            .id(event.id)
                    }
                    if meta.isBusy {
                        ThinkingIndicator(since: busySince, label: busyLabel)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .onAppear { atBottom = true }
                        .onDisappear { atBottom = false }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: session.events) { _ in
                if atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: meta.isBusy) { _ in
                if atBottom { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: inputFocused) { focused in
                if focused {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !atBottom && !session.events.isEmpty {
                    Button {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.userBubble))
                            .shadow(radius: 3)
                    }
                    .padding(12)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle")
                .font(.system(size: 34))
                .foregroundColor(.claudeAccent)
            Text("Hỏi \(meta.toolName) bất cứ điều gì")
                .font(.headline)
            Text("Chạy trên máy tính trong thư mục\n\(meta.cwd)")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// Dong trang thai khi dang chay: buoc cong cu dang chay hoac "Dang suy nghi"
    private var busyLabel: String {
        if meta.status == "waiting" { return "Đang chờ bạn cho phép" }
        if let last = session.events.last {
            if last.kind == "tool", last.status == "running" {
                return "Đang " + (last.title ?? "làm việc").lowercased() + "…"
            }
            if last.kind == "text", last.streaming == true { return "Đang viết…" }
        }
        return "Đang suy nghĩ…"
    }

    private var actions: ChatActions {
        ChatActions(
            openFile: { path, size in openFile(path, size: size) },
            fetchFile: { [api, chatId = meta.id] file in
                guard let path = file.path else { throw APIError.networkError("Không có đường dẫn file") }
                return try await api.downloadFile(chatId: chatId, path: path, size: file.size, mtime: file.mtime)
            },
            preview: { url in previewURL = url },
            answer: { event, decision, answers in answer(event, decision, answers) }
        )
    }

    // MARK: - O nhap

    private var composer: some View {
        VStack(spacing: 8) {
            if let errorText = errorText {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text(errorText).font(.footnote).foregroundColor(.red)
                    Spacer()
                    Button { self.errorText = nil } label: { Image(systemName: "xmark").font(.caption) }
                        .foregroundColor(.secondary)
                }
            }

            if !attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attachments) { f in
                            HStack(spacing: 6) {
                                Image(systemName: FileIcon.name(for: f.name)).foregroundColor(.claudeAccent)
                                Text(f.name).font(.caption).lineLimit(1).frame(maxWidth: 140)
                                Button {
                                    attachments.removeAll { $0.id == f.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .disabled(sending)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            let suggestions = SlashCommand.filter(commands, draft: draft)
            if !suggestions.isEmpty {
                CommandSuggestions(commands: suggestions) { cmd in
                    draft = "/" + cmd.name + (cmd.args == true ? " " : "")
                    inputFocused = true
                }
            }

            VStack(spacing: 6) {
                TextField("Nhắn cho \(meta.toolName)…", text: $draft, axis: .vertical)
                    .lineLimit(1...8)
                    .focused($inputFocused)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)

                HStack(spacing: 14) {
                    Menu {
                        Button {
                            showPhotos = true
                        } label: {
                            Label("Ảnh", systemImage: "photo.on.rectangle")
                        }
                        Button {
                            showImporter = true
                        } label: {
                            Label("File", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.medium))
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().stroke(Color.secondary.opacity(0.4)))
                    }
                    .disabled(sending)

                    modeMenu

                    Spacer()

                    if let progress = progress {
                        Text(progress).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                    }

                    if meta.isBusy && !sending {
                        Button(action: stop) {
                            Image(systemName: "stop.fill")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.black)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Color.white))
                        }
                        .accessibilityLabel("Dừng")
                    } else {
                        Button(action: send) {
                            Group {
                                if sending {
                                    ProgressView().tint(.white)
                                } else {
                                    Image(systemName: "arrow.up").font(.body.weight(.bold))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(canSend ? Color.claudeAccent : Color.gray.opacity(0.4)))
                        }
                        .disabled(!canSend)
                        .accessibilityLabel("Gửi")
                    }
                }
            }
            .padding(10)
            .background(Color.userBubble)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.chatBackground)
    }

    private func loadCommands() async {
        if let list = try? await api.commands(chatId: meta.id) { commands = list }
    }

    private var canSend: Bool {
        !sending && !meta.isBusy && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty)
    }

    private var modeMenu: some View {
        let current = ChatMode.find(meta.mode, tool: meta.tool)
        return Menu {
            ForEach(ChatMode.modes(for: meta.tool)) { mode in
                Button {
                    setMode(mode.id)
                } label: {
                    Label {
                        Text(mode.title) + Text("\n" + mode.subtitle)
                    } icon: {
                        Image(systemName: mode.id == meta.mode ? "checkmark" : mode.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: current.icon)
                Text(current.title)
                Image(systemName: "chevron.down").font(.caption2)
            }
            .font(.caption.weight(.medium))
            .foregroundColor(current.id == "bypassPermissions" || current.id == "skip" ? .claudeAccent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().stroke(Color.secondary.opacity(0.35)))
        }
    }

    // MARK: - Thao tac

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = attachments
        guard canSend else { return }
        sending = true
        errorText = nil
        draft = ""
        attachments = []
        // Bo go tieng Viet (Telex/VNI) dang giu chu dang go do (marked text) se ghi lai chu vao o
        // sau khi xoa -> xoa them lan nua khi bo go da chot, neu o chi con chu cua tin vua gui
        for delay in [0.05, 0.25, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let left = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if errorText == nil && !left.isEmpty && text.contains(left) { draft = "" }
            }
        }
        let api = self.api
        let chatId = meta.id

        Task {
            do {
                var turn: Int?
                if !files.isEmpty {
                    progress = "Đang tạo lượt…"
                    let created = try await api.createTurn(chatId: chatId)
                    for (i, f) in files.enumerated() {
                        progress = "Đang tải \(i + 1)/\(files.count)…"
                        try await api.uploadFile(chatId: chatId, turn: created.turn, fileURL: f.url, name: f.name)
                    }
                    turn = created.turn
                }
                progress = nil
                try await api.sendMessage(chatId: chatId, text: text, turn: turn)
                for f in files {
                    try? FileManager.default.removeItem(at: f.url.deletingLastPathComponent())
                }
                busySince = Date()
            } catch {
                progress = nil
                errorText = error.localizedDescription
                if draft.isEmpty { draft = text }
                if attachments.isEmpty { attachments = files }
            }
            sending = false
        }
    }

    private func stop() {
        let api = self.api
        let chatId = meta.id
        Task {
            do {
                try await api.interrupt(chatId: chatId)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func answer(_ event: ChatEvent, _ decision: PermissionDecision, _ answers: [String: String]?) {
        guard let requestId = event.requestId else { return }
        session.updateLocally(event.id) { e in
            e.status = decision == .deny ? "denied" : "allowed"
            if let answers = answers { e.answers = answers }
        }
        let api = self.api
        let chatId = meta.id
        Task {
            do {
                try await api.answerPermission(chatId: chatId, requestId: requestId, decision: decision, answers: answers)
            } catch {
                errorText = error.localizedDescription
                session.updateLocally(event.id) { e in e.status = "pending" }
            }
        }
    }

    private func setMode(_ mode: String) {
        let api = self.api
        let chatId = meta.id
        Task {
            do {
                let updated = try await api.updateChat(id: chatId, mode: mode)
                session.setMeta(updated)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func rename() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let api = self.api
        let chatId = meta.id
        Task {
            do {
                let updated = try await api.updateChat(id: chatId, name: name)
                session.setMeta(updated)
                store.upsert(updated)
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func openFile(_ path: String, size: Int64?) {
        guard !downloading else { return }
        downloading = true
        let api = self.api
        let chatId = meta.id
        Task {
            do {
                previewURL = try await api.downloadFile(chatId: chatId, path: path, size: size)
            } catch {
                errorText = error.localizedDescription
            }
            downloading = false
        }
    }

    static func folderName(_ path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }

    // MARK: - Dinh kem

    struct PickedFile: Identifiable {
        let id = UUID()
        let url: URL      // ban sao trong thu muc tam
        let name: String
    }

    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SendFiles", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Ten khong trung voi file da chon (server cung tu them (2) neu trung tren PC)
    private func uniqueName(_ name: String) -> String {
        let existing = Set(attachments.map(\.name))
        guard existing.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var i = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) (\(i))" : "\(base) (\(i)).\(ext)"
            if !existing.contains(candidate) { return candidate }
            i += 1
        }
    }

    private func addImported(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let name = uniqueName(url.lastPathComponent)
            let dest = Self.makeTempDir().appendingPathComponent(name)
            do {
                try FileManager.default.copyItem(at: url, to: dest)
                attachments.append(PickedFile(url: dest, name: name))
            } catch {
                errorText = "Không đọc được \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    /// Anh chuyen sang JPEG (Claude/agy khong doc duoc HEIC)
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        progress = "Đang chuẩn bị ảnh…"
        defer { progress = nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                errorText = "Không đọc được ảnh thứ \(index + 1)"
                continue
            }
            var output = data
            var ext = "jpg"
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .png) }) {
                ext = "png"
            } else if !item.supportedContentTypes.contains(where: { $0.conforms(to: .jpeg) }),
                      let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) {
                output = jpeg
            }
            let name = uniqueName("Ảnh \(stamp)-\(index + 1).\(ext)")
            let dest = Self.makeTempDir().appendingPathComponent(name)
            do {
                try output.write(to: dest)
                attachments.append(PickedFile(url: dest, name: name))
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}

// MARK: - Dang suy nghi

struct ThinkingIndicator: View {
    let since: Date?
    let label: String
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle")
                .foregroundColor(.claudeAccent)
                .scaleEffect(pulse ? 1.15 : 0.85)
                .opacity(pulse ? 1 : 0.6)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(label + elapsed(context.date))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear { pulse = true }
    }

    private func elapsed(_ now: Date) -> String {
        guard let since = since else { return "" }
        let s = max(0, Int(now.timeIntervalSince(since)))
        return s < 60 ? " \(s)s" : " \(s / 60)m \(s % 60)s"
    }
}
