//
//  ChatListView.swift
//  ClaudeRemote
//
//  Danh sach cuoc chat (luu tren PC, moi nhat truoc) + mo lai phien Claude cu tren may.
//

import SwiftUI

enum ChatRoute: Hashable {
    case chat(String)
    case history
}

struct ChatListView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ChatStore
    @Binding var path: NavigationPath
    @Binding var showSettings: Bool

    @State private var showNew = false
    @State private var pendingDelete: ChatMeta?

    var body: some View {
        List {
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(.red)
                    .listRowBackground(Color.red.opacity(0.12))
            }

            Section {
                NavigationLink(value: ChatRoute.history) {
                    Label("Mở lại phiên Claude cũ trên máy", systemImage: "clock.arrow.circlepath")
                        .foregroundColor(.claudeAccent)
                }
            }

            if store.loaded && store.chats.isEmpty && store.errorMessage == nil {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("Chưa có cuộc chat nào.\nBấm biểu tượng bút ở góc trên để bắt đầu.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .listRowBackground(Color.clear)
            }

            ForEach(groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.chats) { chat in
                        NavigationLink(value: ChatRoute.chat(chat.id)) {
                            ChatRow(chat: chat)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                pendingDelete = chat
                            } label: {
                                Label("Xoá", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Text("Phiên bản \(AppSettings.versionText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.chatBackground.ignoresSafeArea())
        .navigationTitle("Claude Remote")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showNew = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(!settings.isConfigured)
            }
        }
        .refreshable { await store.refresh(settings: settings) }
        // Lam moi 5s de thay trang thai dang chay / cho cho phep
        .task {
            while !Task.isCancelled {
                await store.refresh(settings: settings)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .sheet(isPresented: $showNew) {
            NewChatView { chat in
                store.upsert(chat)
                path.append(ChatRoute.chat(chat.id))
            }
        }
        .confirmationDialog(
            "Xoá cuộc chat \"\(pendingDelete?.name ?? "")\"?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Xoá", role: .destructive) {
                if let chat = pendingDelete {
                    Task { await store.delete(chat, settings: settings) }
                }
                pendingDelete = nil
            }
        } message: {
            Text("Lịch sử chat trên server sẽ bị xoá. File trên máy tính vẫn giữ nguyên.")
        }
    }

    private struct Group {
        let title: String
        let chats: [ChatMeta]
    }

    private var groups: [Group] {
        let cal = Calendar.current
        var buckets: [(String, [ChatMeta])] = [("Hôm nay", []), ("Hôm qua", []), ("7 ngày qua", []), ("Cũ hơn", [])]
        for chat in store.chats {
            let date = ChatRow.parseDate(chat.updatedAt) ?? .distantPast
            let i: Int
            if cal.isDateInToday(date) { i = 0 }
            else if cal.isDateInYesterday(date) { i = 1 }
            else if date > Date().addingTimeInterval(-7 * 86400) { i = 2 }
            else { i = 3 }
            buckets[i].1.append(chat)
        }
        return buckets.filter { !$0.1.isEmpty }.map { Group(title: $0.0, chats: $0.1) }
    }
}

struct ChatRow: View {
    let chat: ChatMeta

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: chat.tool == "agy" ? "a.circle.fill" : "sparkle")
                .font(.title3)
                .foregroundColor(chat.tool == "agy" ? .blue : .claudeAccent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(chat.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    if let date = Self.parseDate(chat.updatedAt) {
                        Text(Self.relative(date))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                if chat.status == "waiting" {
                    Label("Đang chờ bạn cho phép", systemImage: "hand.raised.fill")
                        .font(.caption)
                        .foregroundColor(.claudeAccent)
                } else if chat.status == "running" {
                    Label("Đang chạy…", systemImage: "circle.dotted")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if let preview = chat.preview, !preview.isEmpty {
                    Text(Self.plain(preview))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Text(chat.cwd)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.vertical, 2)
    }

    /// "2 phút trước"
    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.unitsStyle = .full
        return f.localizedString(for: min(date, Date()), relativeTo: Date())
    }

    /// Bo ky hieu markdown trong dong xem truoc
    static func plain(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(^|\s)#{1,6}\s"#, with: "$1", options: .regularExpression)
        for mark in ["**", "__", "`"] { t = t.replacingOccurrences(of: mark, with: "") }
        return t
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

// MARK: - Chat moi

struct NewChatView: View {
    var onCreated: (ChatMeta) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var name = ""
    @State private var cwd = ""
    @State private var tool = "claude"
    @State private var mode = "default"
    @State private var submitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Trợ lý", selection: $tool) {
                        Text("Claude").tag("claude")
                        Text("agy").tag("agy")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: tool) { t in
                        mode = ChatMode.modes(for: t).first?.id ?? "default"
                    }
                }

                Section("Thư mục làm việc trên máy tính") {
                    TextField("C:\\Users\\ducle\\Code", text: $cwd)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                    ForEach(settings.recentDirs, id: \.self) { dir in
                        Button {
                            cwd = dir
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text(dir).lineLimit(1).truncationMode(.head)
                                Spacer()
                                if cwd == dir { Image(systemName: "checkmark").foregroundColor(.claudeAccent) }
                            }
                            .font(.footnote)
                        }
                        .foregroundColor(.primary)
                    }
                }

                Section("Tên (không bắt buộc)") {
                    TextField("Mặc định là tên thư mục", text: $name)
                }

                Section("Quyền") {
                    ForEach(ChatMode.modes(for: tool)) { m in
                        Button {
                            mode = m.id
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: m.icon).frame(width: 22).foregroundColor(.claudeAccent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.title).foregroundColor(.primary)
                                    Text(m.subtitle).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if mode == m.id { Image(systemName: "checkmark").foregroundColor(.claudeAccent) }
                            }
                        }
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Chat mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }.disabled(submitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("Bắt đầu") { create() }
                            .fontWeight(.bold)
                            .disabled(cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .onAppear {
                if cwd.isEmpty { cwd = settings.recentDirs.first ?? "" }
            }
        }
    }

    private func create() {
        let dir = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        submitting = true
        errorMessage = nil
        Task {
            do {
                let chat = try await settings.makeAPI().createChat(
                    cwd: dir, name: name.trimmingCharacters(in: .whitespacesAndNewlines), tool: tool, mode: mode
                )
                settings.addRecentDir(dir)
                dismiss()
                onCreated(chat)
            } catch {
                errorMessage = error.localizedDescription
            }
            submitting = false
        }
    }
}

// MARK: - Phien Claude cu tren may

struct HistoryView: View {
    var onOpened: (ChatMeta) -> Void

    @EnvironmentObject private var settings: AppSettings
    @State private var items: [ClaudeHistoryItem] = []
    @State private var loading = true
    @State private var opening: String?
    @State private var errorMessage: String?
    @State private var search = ""

    private var filtered: [ClaudeHistoryItem] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(q) || $0.cwd.lowercased().contains(q) || ($0.lastPrompt ?? "").lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            if let errorMessage = errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if items.isEmpty && errorMessage == nil {
                Text("Không tìm thấy phiên Claude nào trên máy tính.")
                    .foregroundColor(.secondary)
            }
            Section {
                ForEach(filtered) { item in
                    Button {
                        open(item)
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.body.weight(.medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                if let last = item.lastPrompt, last != item.title {
                                    Text(last)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                HStack(spacing: 6) {
                                    Image(systemName: "folder")
                                    Text(ChatView.folderName(item.cwd))
                                    if let date = ChatRow.parseDate(item.updatedAt) {
                                        Text("· " + ChatRow.relative(date))
                                    }
                                }
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.8))
                            }
                            Spacer()
                            if opening == item.id { ProgressView() }
                        }
                    }
                    .disabled(opening != nil)
                }
            } footer: {
                Text("Mở lại sẽ tải lịch sử phiên đó vào app. Gửi tin là Claude tiếp tục đúng cuộc trò chuyện cũ trên máy tính.")
            }
        }
        .searchable(text: $search, prompt: "Tìm phiên")
        .scrollContentBackground(.hidden)
        .background(Color.chatBackground.ignoresSafeArea())
        .navigationTitle("Phiên Claude cũ")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            items = try await settings.makeAPI().claudeHistory()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }

    private func open(_ item: ClaudeHistoryItem) {
        opening = item.id
        Task {
            do {
                let chat = try await settings.makeAPI().resumeClaudeSession(item)
                onOpened(chat)
            } catch {
                errorMessage = error.localizedDescription
            }
            opening = nil
        }
    }
}
