//
//  SessionStore.swift
//  ClaudeRemote
//
//  Quan ly danh sach va trang thai cac phien lam viec (Session) cho toan bo UI.
//

import Foundation
import Combine

@MainActor
public final class SessionStore: ObservableObject {
    @Published public var sessions: [Session] = []
    @Published public var error: String? = nil
    @Published public var loading: Bool = false

    public init() {}

    /// Lam moi danh sach cac phien tu server. Khong xoa danh sach cu khi gap loi.
    public func refresh(settings: AppSettings) async {
        guard settings.isConfigured else {
            self.error = APIError.missingConfiguration.localizedDescription
            return
        }

        loading = true
        error = nil
        defer { loading = false }

        let api = settings.makeAPI()
        do {
            let fetched = try await api.listSessions()
            self.sessions = fetched
            self.error = nil
        } catch {
            // Khong xoa danh sach cu khi loi, chi ghi nhan loi
            self.error = error.localizedDescription
        }
    }

    /// Xoa mot phien lam viec theo ID tren server va cap nhat danh sach phien.
    public func delete(id: String, settings: AppSettings) async {
        guard settings.isConfigured else {
            self.error = APIError.missingConfiguration.localizedDescription
            return
        }

        loading = true
        error = nil
        defer { loading = false }

        let api = settings.makeAPI()
        do {
            try await api.deleteSession(id: id)
            self.sessions.removeAll { $0.id == id }
            self.error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
