//
//  ChatStore.swift
//  ClaudeRemote
//
//  Danh sach chat tren server (moi nhat truoc).
//

import Foundation
import Combine

@MainActor
final class ChatStore: ObservableObject {
    @Published private(set) var chats: [ChatMeta] = []
    @Published var errorMessage: String?
    @Published private(set) var loaded = false

    func refresh(settings: AppSettings) async {
        guard settings.isConfigured else { return }
        do {
            let list = try await settings.makeAPI().listChats()
            if list != chats { chats = list }
            if errorMessage != nil { errorMessage = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
        loaded = true
    }

    func upsert(_ chat: ChatMeta) {
        if let i = chats.firstIndex(where: { $0.id == chat.id }) {
            chats[i] = chat
        } else {
            chats.insert(chat, at: 0)
        }
    }

    func delete(_ chat: ChatMeta, settings: AppSettings) async {
        do {
            try await settings.makeAPI().deleteChat(id: chat.id)
            chats.removeAll { $0.id == chat.id }
            ChatSession.removeCache(chatId: chat.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
