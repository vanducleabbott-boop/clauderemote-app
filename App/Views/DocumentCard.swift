//
//  DocumentCard.swift
//  ClaudeRemote
//
//  The file ket qua: tu tai file tu PC ve iPhone ngay khi hien, anh trang dau (PDF, Word, Excel,
//  PowerPoint, text...) bang QLThumbnailGenerator. Cham de xem trong app, nut chia se de mo app khac.
//

import SwiftUI
import QuickLookThumbnailing

struct DocumentCard: View {
    let file: ChatFile
    let actions: ChatActions
    /// It file: anh trang dau lon; nhieu file: dong gon
    var large: Bool = true

    /// File lon hon muc nay chi tai khi cham vao (tranh ton 4G)
    static let autoDownloadLimit: Int64 = 30 * 1024 * 1024

    @State private var localURL: URL?
    @State private var thumbnail: UIImage?
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if large {
                previewArea
                    .frame(maxWidth: .infinity)
                    .frame(height: 190)
                    .clipped()
            }
            HStack(spacing: 10) {
                if !large { smallThumb }
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(errorText == nil ? .secondary : .red)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let url = localURL {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .frame(width: 36, height: 36)
                    }
                    .foregroundColor(.claudeAccent)
                } else if loading {
                    ProgressView().frame(width: 36, height: 36)
                }
            }
            .padding(10)
        }
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.08)))
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .task(id: file.id + String(file.mtime ?? 0)) {
            guard (file.size ?? 0) <= Self.autoDownloadLimit else { return }
            await download()
        }
    }

    private var subtitle: String {
        if let errorText = errorText { return errorText }
        var parts = [FileIcon.kind(for: file.name)]
        if let size = file.size { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        if loading { parts.append("đang tải…") } else if localURL != nil { parts.append("chạm để xem") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var previewArea: some View {
        ZStack {
            Color.white.opacity(0.04)
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                    .padding(.top, 12)
                    .padding(.horizontal, 12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: FileIcon.name(for: file.name))
                        .font(.system(size: 40))
                        .foregroundColor(FileIcon.color(for: file.name))
                    Text(FileIcon.kind(for: file.name))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var smallThumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(FileIcon.color(for: file.name).opacity(0.15))
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail).resizable().scaledToFill()
            } else {
                Image(systemName: FileIcon.name(for: file.name))
                    .foregroundColor(FileIcon.color(for: file.name))
            }
        }
        .frame(width: 40, height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func open() {
        if let url = localURL {
            actions.preview(url)
            return
        }
        Task {
            await download()
            if let url = localURL { actions.preview(url) }
        }
    }

    @MainActor private func download() async {
        guard localURL == nil, !loading else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            let url = try await actions.fetchFile(file)
            localURL = url
            thumbnail = await Self.makeThumbnail(url, large: large)
        } catch {
            errorText = error.localizedDescription
        }
    }

    static func makeThumbnail(_ url: URL, large: Bool) async -> UIImage? {
        let size = large ? CGSize(width: 240, height: 320) : CGSize(width: 40, height: 50)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: UIScreen.main.scale, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
    }
}
