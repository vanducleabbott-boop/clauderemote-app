//
//  RootView.swift
//  ClaudeRemote
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ChatStore
    @State private var showSettings = false
    @State private var path = NavigationPath()
    @ObservedObject private var watcher = BackgroundWatcher.shared
    @ObservedObject private var access = CloudflareAccess.shared
    @State private var refreshWarning: Bool = false

    private var isWarningVisible: Bool {
        _ = refreshWarning
        _ = access.showLogin
        return CloudflareAccess.daysLeftWarning
    }

    @ViewBuilder
    private var expiryBanner: some View {
        if isWarningVisible, let exp = CloudflareAccess.expiryDate {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.black)
                Text("Phiên Cloudflare hết hạn \(CloudflareAccess.formatExpiry(exp))")
                    .font(.footnote)
                    .foregroundColor(.black)
                    .lineLimit(1)
                Spacer()
                Button("Đăng nhập lại") {
                    CloudflareAccess.clear()
                    refreshWarning.toggle()
                    if let url = URL(string: ServerAPI.normalizeBaseURL(settings.baseURL)) {
                        access.requestLogin(baseURL: url)
                    }
                }
                .font(.footnote.weight(.semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.15))
                .cornerRadius(6)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.yellow)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ChatListView(path: $path, showSettings: $showSettings)
                .navigationDestination(for: ChatRoute.self) { route in
                    switch route {
                    case .chat(let id):
                        if let meta = store.chats.first(where: { $0.id == id }) {
                            ChatView(meta: meta, api: settings.makeAPI())
                                .id(id)
                        } else {
                            Text("Không tìm thấy cuộc chat").foregroundColor(.secondary)
                        }
                    case .history:
                        HistoryView { chat in
                            store.upsert(chat)
                            path.removeLast()
                            path.append(ChatRoute.chat(chat.id))
                        }
                    }
                }
        }
        .tint(.claudeAccent)
        .safeAreaInset(edge: .top, spacing: 0) {
            expiryBanner
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: Binding(
            get: { access.showLogin && !showSettings },
            set: { access.showLogin = $0 }
        )) {
            let normalized = ServerAPI.normalizeBaseURL(settings.baseURL)
            let fallbackURL = URL(string: normalized)
            CloudflareLoginSheet(baseURL: access.loginURL ?? fallbackURL) {
                refreshWarning.toggle()
            }
        }
        .onAppear {
            refreshWarning.toggle()
            if !settings.isConfigured {
                showSettings = true
            } else if let url = URL(string: ServerAPI.normalizeBaseURL(settings.baseURL)), url.scheme != nil {
                if CloudflareAccess.cookie == nil {
                    access.requestLogin(baseURL: url)
                } else {
                    Task {
                        await CloudflareAccess.preloadWebCookies(for: url)
                    }
                    CloudflareAccess.scheduleExpiryNotification()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudflareAccess.didLoginNotification)) { _ in
            refreshWarning.toggle()
        }
        .onChange(of: access.showLogin) { _ in
            refreshWarning.toggle()
        }
        .onChange(of: showSettings) { isShown in
            if !isShown {
                refreshWarning.toggle()
            }
        }
        // Cham vao thong bao "da xong" -> mo dung chat
        .onReceive(watcher.$pendingChatId.compactMap { $0 }) { id in
            watcher.pendingChatId = nil
            Task {
                await store.refresh(settings: settings)
                path = NavigationPath()
                path.append(ChatRoute.chat(id))
            }
        }
        // Tham so khoi dong "-openChat <id>": mo thang 1 chat (chay thu tren may ao)
        .task {
            guard let id = UserDefaults.standard.string(forKey: "openChat") else { return }
            await store.refresh(settings: settings)
            path.append(ChatRoute.chat(id))
        }
    }
}
