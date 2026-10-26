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
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            if !settings.isConfigured {
                showSettings = true
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
