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
        }
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
        .task {
            while !Task.isCancelled {
                await store.refresh(settings: settings)
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
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

                if let clients = session.clients, clients > 0 {
                    Spacer()
                    Text("\(clients) máy")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
