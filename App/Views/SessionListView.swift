//
//  SessionListView.swift
//  ClaudeRemote
//

import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: SessionStore

    @State private var showNewSession: Bool = false
    @State private var showSettings: Bool = false
    @Environment(\.scenePhase) private var scenePhase
    /// Tang len de tinh lai danh sach lich su tren may sau khi xoa
    @State private var localVersion: Int = 0

    /// Lich su luu tren iPhone cua cac phien khong con tren server
    private var localOnly: [SessionLogStore.Meta] {
        _ = localVersion
        let ids = Set(store.sessions.map(\.id))
        return SessionLogStore.shared.allMetas().filter { !ids.contains($0.id) }
    }

    var body: some View {
        List {
            if let error = store.error {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(8)
                .background(Color.red.opacity(0.15))
                .cornerRadius(8)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if store.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Chưa có phiên nào. Bấm + để tạo.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 32)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.sessions) { session in
                    NavigationLink(destination: TerminalScreen(session: session)) {
                        sessionRow(session)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            Task {
                                await store.delete(id: session.id, settings: settings)
                                await store.refresh(settings: settings)
                            }
                        } label: {
                            Label("Xóa", systemImage: "trash")
                        }
                    }
                }
            }

            if !localOnly.isEmpty {
                Section("Lịch sử trên máy (phiên đã đóng)") {
                    ForEach(localOnly) { meta in
                        NavigationLink(destination: TerminalScreen(session: Self.session(from: meta), readOnly: true)) {
                            localRow(meta)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                SessionLogStore.shared.remove(id: meta.id)
                                localVersion += 1
                            } label: {
                                Label("Xóa", systemImage: "trash")
                            }
                        }
                    }
                }
            }

            Section {
                Text("Claude Remote \(AppSettings.versionText)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .onAppear { localVersion += 1 }
        .navigationTitle("Phiên terminal")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Cài đặt")

                    Button {
                        showNewSession = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Tạo phiên mới")
                }
            }
        }
        .sheet(isPresented: $showNewSession) {
            NewSessionView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .refreshable {
            await store.refresh(settings: settings)
        }
        // Chi poll khi man hinh danh sach dang hien va app o foreground
        // (.task tu huy khi mo terminal de khong lam terminal bi ve lai moi 3s)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await store.refresh(settings: settings)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private static func session(from meta: SessionLogStore.Meta) -> Session {
        Session(id: meta.id, name: meta.name, cwd: meta.cwd, mode: "normal", tool: meta.tool, status: "exited")
    }

    private static func formatSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    @ViewBuilder
    private func localRow(_ meta: SessionLogStore.Meta) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meta.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(Self.formatSize(meta.bytes))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(meta.cwd)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(session.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                // Chip tool ("claude" màu cam / "agy" màu xanh)
                Text(session.tool)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(session.tool.lowercased() == "agy" ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundColor(session.tool.lowercased() == "agy" ? Color.blue : Color.orange)
                    .clipShape(Capsule())

                // Chip trạng thái ("Đang chạy" xanh lá / "Đã thoát" xám)
                Text(session.isRunning ? "Đang chạy" : "Đã thoát")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(session.isRunning ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
                    .foregroundColor(session.isRunning ? Color.green : Color.gray)
                    .clipShape(Capsule())
            }

            HStack(alignment: .center, spacing: 8) {
                Text(session.cwd)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()
                if let saved = SessionLogStore.shared.meta(for: session.id), saved.bytes > 0 {
                    // Dung luong lich su da luu tren iPhone
                    Text(Self.formatSize(saved.bytes))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if let clients = session.clients, clients > 0 {
                    Text("\(clients) máy")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
