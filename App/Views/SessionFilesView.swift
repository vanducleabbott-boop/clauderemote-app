//
//  SessionFilesView.swift
//  ClaudeRemote
//
//  Tab File cua phien: moi luot hien file Gui len va Ket qua (Claude/agy luu vao),
//  luot moi nhat o tren. Bam file de xem (QuickLook, co nut chia se). Nut + gui file (luot moi).
//

import SwiftUI
import QuickLook

struct SessionFilesView: View {
    let session: Session
    @EnvironmentObject private var settings: AppSettings

    @State private var listing: FilesListing?
    @State private var error: String?
    @State private var showSend = false
    @State private var previewURL: URL?
    @State private var downloading: String?

    var body: some View {
        List {
            if let error = error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundColor(.red)
                    .listRowBackground(Color.red.opacity(0.12))
            }

            if let listing = listing, listing.turns.isEmpty {
                emptyState
            } else if listing == nil && error == nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            ForEach(listing?.turns ?? []) { turn in
                Section {
                    groupHeader("Gửi lên", systemImage: "arrow.up.circle.fill", color: .blue)
                    if turn.uploads.isEmpty {
                        placeholder("Chưa có file")
                    }
                    ForEach(turn.uploads) { file in
                        fileRow(file, turn: turn.turn, kind: .uploads)
                    }

                    groupHeader("Kết quả", systemImage: "arrow.down.circle.fill", color: .green)
                    if turn.results.isEmpty {
                        placeholder("Đang chờ \(session.tool == "agy" ? "agy" : "Claude") xử lý…")
                    }
                    ForEach(turn.results) { file in
                        fileRow(file, turn: turn.turn, kind: .results)
                    }
                } header: {
                    Text("Lượt \(turn.turn)")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
            }

            if let folder = listing?.folder {
                Section {
                    Text(folder)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                } header: {
                    Text("Thư mục trên PC").textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await load() }
        // Tu lam moi 5s khi dang mo tab (ket qua xuat hien khi Claude/agy xu ly xong)
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showSend = true
            } label: {
                Image(systemName: "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(radius: 4)
            }
            .padding(20)
            .accessibilityLabel("Gửi file (lượt mới)")
        }
        .sheet(isPresented: $showSend) {
            SendFilesView(session: session) {
                Task { await load() }
            }
        }
        .quickLookPreview($previewURL)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.up")
                .font(.system(size: 36))
                .foregroundColor(.secondary)
            Text("Chưa gửi file nào trong phiên này.\nBấm + để gửi file cho \(session.tool == "agy" ? "agy" : "Claude").")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .listRowBackground(Color.clear)
    }

    private func groupHeader(_ title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(color)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .padding(.leading, 28)
    }

    private func fileRow(_ file: RemoteFile, turn: Int, kind: FileKind) -> some View {
        let key = "\(turn)/\(kind.rawValue)/\(file.name)"
        return Button {
            open(file, turn: turn, kind: kind)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: Self.icon(for: file.name))
                    .foregroundColor(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if downloading == key {
                    ProgressView()
                }
            }
            .padding(.leading, 6)
        }
        .disabled(downloading != nil)
    }

    private func open(_ file: RemoteFile, turn: Int, kind: FileKind) {
        let key = "\(turn)/\(kind.rawValue)/\(file.name)"
        downloading = key
        let api = settings.makeAPI()
        Task {
            do {
                previewURL = try await api.downloadFile(sessionId: session.id, turn: turn, kind: kind, file: file)
            } catch {
                self.error = error.localizedDescription
            }
            downloading = nil
        }
    }

    private func load() async {
        do {
            let fetched = try await settings.makeAPI().listFiles(sessionId: session.id)
            if fetched != listing {
                listing = fetched
            }
            if error != nil {
                error = nil
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    static func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
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
