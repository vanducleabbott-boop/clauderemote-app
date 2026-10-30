import SwiftUI
import QuickLook

/// Danh sach file trong 1 thu muc tren PC (link thu muc trong tra loi). Cham file de xem, cham thu muc de vao trong.
struct RemoteFolderView: View {
    let folder: RemoteFolder
    let api: ServerAPI
    let chatId: String

    @Environment(\.dismiss) private var dismiss
    @State private var stack: [RemoteFolder] = []
    @State private var previewURL: URL?
    @State private var loadingPath: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack(path: $stack) {
            list(folder)
                .navigationDestination(for: RemoteFolder.self) { list($0) }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Xong") { dismiss() }
                    }
                }
        }
        .quickLookPreview($previewURL)
    }

    private func list(_ f: RemoteFolder) -> some View {
        List {
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
            if f.entries.isEmpty {
                Text("Thư mục trống").foregroundStyle(.secondary)
            }
            ForEach(f.entries) { e in
                Button { open(e) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: e.dir ? "folder.fill" : "doc")
                            .foregroundStyle(e.dir ? Color.claudeAccent : .secondary)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.name).foregroundStyle(.primary).lineLimit(2)
                            if let size = e.size {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if loadingPath == e.path {
                            ProgressView()
                        } else if e.dir {
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .disabled(loadingPath != nil)
            }
        }
        .navigationTitle(f.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func open(_ e: RemoteFolder.Entry) {
        loadingPath = e.path
        errorText = nil
        Task {
            do {
                previewURL = try await api.downloadFile(chatId: chatId, path: e.path, size: e.size)
            } catch let opened as RemoteFolderOpened {
                stack.append(opened.folder)
            } catch {
                errorText = error.localizedDescription
            }
            loadingPath = nil
        }
    }
}

extension RemoteFolder: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

extension RemoteFolder.Entry: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(path) }
}
