//
//  SendFilesView.swift
//  ClaudeRemote
//
//  Gui file cho Claude/agy: chon anh/file + nhap yeu cau -> tao luot moi, upload tung file,
//  server go yeu cau (kem duong dan Gui len / Ket qua) vao phien.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct SendFilesView: View {
    let session: Session
    var onSent: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    struct PickedFile: Identifiable {
        let id = UUID()
        let url: URL      // ban sao trong thu muc tam
        let name: String
        let size: Int64
    }

    @State private var message = ""
    @State private var files: [PickedFile] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showImporter = false
    @State private var preparing = false
    @State private var sending = false
    @State private var progress: String?
    @State private var error: String?

    private var toolName: String { session.tool == "agy" ? "agy" : "Claude" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ví dụ: tóm tắt file này, dịch sang tiếng Anh…", text: $message, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Yêu cầu cho \(toolName)")
                } footer: {
                    Text("Để trống thì \(toolName) sẽ được nhờ đọc và xử lý file. Kết quả lưu vào thư mục Kết quả của lượt này.")
                }

                Section {
                    PhotosPicker(selection: $photoItems, maxSelectionCount: 20, matching: .images) {
                        Label("Chọn ảnh", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Label("Chọn file", systemImage: "folder")
                    }
                    if preparing {
                        HStack {
                            ProgressView()
                            Text("Đang chuẩn bị…").foregroundColor(.secondary)
                        }
                    }
                }

                if !files.isEmpty {
                    Section("Sẽ gửi (\(files.count))") {
                        ForEach(files) { f in
                            HStack {
                                Image(systemName: SessionFilesView.icon(for: f.name))
                                    .foregroundColor(.secondary)
                                Text(f.name).lineLimit(2)
                                Spacer()
                                Text(ByteCountFormatter.string(fromByteCount: f.size, countStyle: .file))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onDelete { files.remove(atOffsets: $0) }
                    }
                }

                if let progress = progress {
                    Section {
                        HStack {
                            ProgressView()
                            Text(progress)
                        }
                    }
                }

                if let error = error {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Gửi file – lượt mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                        .disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gửi") { send() }
                        .fontWeight(.bold)
                        .disabled(files.isEmpty || sending || preparing)
                }
            }
            .interactiveDismissDisabled(sending)
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    addImported(urls)
                case .failure(let err):
                    error = err.localizedDescription
                }
            }
            .onChange(of: photoItems) { items in
                guard !items.isEmpty else { return }
                photoItems = []
                Task { await addPhotos(items) }
            }
        }
    }

    // MARK: - Chuan bi file

    private static func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SendFiles", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
    }

    /// Ten khong trung voi file da chon (server cung tu them (2) neu trung tren PC)
    private func uniqueName(_ name: String) -> String {
        let existing = Set(files.map(\.name))
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
                files.append(PickedFile(url: dest, name: name, size: Self.fileSize(dest)))
            } catch {
                self.error = "Không đọc được \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    /// Anh chuyen sang JPEG (Claude/agy khong doc duoc HEIC)
    private func addPhotos(_ items: [PhotosPickerItem]) async {
        preparing = true
        defer { preparing = false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        for (index, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                error = "Không đọc được ảnh thứ \(index + 1)"
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
                files.append(PickedFile(url: dest, name: name, size: Int64(output.count)))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - Gui

    private func send() {
        sending = true
        error = nil
        let api = settings.makeAPI()
        let toSend = files
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                progress = "Đang tạo lượt mới…"
                let turn = try await api.createTurn(sessionId: session.id)
                for (i, f) in toSend.enumerated() {
                    progress = "Lượt \(turn.turn): đang tải \(i + 1)/\(toSend.count) – \(f.name)"
                    try await api.uploadFile(sessionId: session.id, turn: turn.turn, fileURL: f.url, name: f.name)
                }
                progress = "Đang giao việc cho \(toolName)…"
                let result = try await api.submitTurn(sessionId: session.id, turn: turn.turn, message: text)
                for f in toSend {
                    try? FileManager.default.removeItem(at: f.url.deletingLastPathComponent())
                }
                progress = nil
                sending = false
                if !result.sent {
                    error = "Đã lưu file vào Lượt \(turn.turn) nhưng phiên đã thoát nên chưa giao việc cho \(toolName)."
                    onSent()
                    return
                }
                onSent()
                dismiss()
            } catch {
                progress = nil
                sending = false
                self.error = error.localizedDescription
            }
        }
    }
}
