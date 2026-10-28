//
//  SettingsView.swift
//  ClaudeRemote
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: ChatStore
    @ObservedObject private var watcher = BackgroundWatcher.shared
    @ObservedObject private var access = CloudflareAccess.shared

    @State private var isTesting: Bool = false
    @State private var statusMessage: String? = nil
    @State private var isStatusSuccess: Bool = false
    @State private var refreshExpiry: Bool = false

    private var expiryText: String {
        _ = refreshExpiry
        _ = access.showLogin
        if let exp = CloudflareAccess.expiryDate {
            return CloudflareAccess.formatExpiry(exp)
        } else {
            return "chưa đăng nhập"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("URL máy chủ") {
                    TextField("https://claude.nhaduc.name.vn", text: $settings.baseURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                Section("Token") {
                    SecureField("Token", text: $settings.token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Kiểm tra kết nối")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting || settings.baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || settings.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let message = statusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: isStatusSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isStatusSuccess ? .green : .red)
                            Text(message)
                                .foregroundColor(isStatusSuccess ? .green : .red)
                                .font(.footnote)
                        }
                    }
                }

                Section("Cloudflare") {
                    LabeledContent("Phiên hết hạn", value: expiryText)
                    Button("Đăng nhập lại Cloudflare") {
                        CloudflareAccess.clear()
                        refreshExpiry.toggle()
                        let normalized = ServerAPI.normalizeBaseURL(settings.baseURL)
                        if let url = URL(string: normalized) {
                            access.requestLogin(baseURL: url)
                        }
                    }
                }

                Section {
                    Toggle("Chạy ngầm & báo khi xong", isOn: $watcher.enabled)
                    if watcher.enabled {
                        statusRow(ok: watcher.keepsAlive,
                                  text: watcher.keepsAlive ? "Vị trí: Luôn luôn — app chạy ngầm được" : "Vị trí chưa đặt \"Luôn luôn\" — vào Cài đặt iPhone › Claude Remote › Vị trí để đổi")
                        statusRow(ok: watcher.notifyAllowed,
                                  text: watcher.notifyAllowed ? "Đã cho phép thông báo" : "Chưa cho phép thông báo")
                        Toggle("Ẩn mũi tên định vị", isOn: $watcher.hideArrow)
                        if watcher.hideArrow && watcher.preciseLocation {
                            statusRow(ok: false, text: "\"Vị trí chính xác\" đang bật nên iOS luôn hiện mũi tên — vào Cài đặt iPhone › Claude Remote › Vị trí, tắt \"Vị trí chính xác\"")
                            Button("Mở Cài đặt iPhone") { watcher.openSettings() }
                        }
                        NavigationLink("Nhật ký chạy ngầm") { BackgroundLogView() }
                        if (!watcher.keepsAlive || !watcher.notifyAllowed) && !(watcher.hideArrow && watcher.preciseLocation) {
                            Button("Mở Cài đặt iPhone") { watcher.openSettings() }
                        }
                    }
                } header: {
                    Text("Thông báo")
                } footer: {
                    Text("Báo khi Claude / agy làm xong hoặc cần bạn trả lời, kể cả khi bạn đang dùng app khác. App dùng quyền vị trí (độ chính xác thấp, không gửi đi đâu) chỉ để iOS cho chạy ngầm, giống app Clip. Nếu app bị vuốt tắt sẽ có thông báo nhắc mở lại app. \"Ẩn mũi tên định vị\": không hiện mũi tên xanh cạnh camera (giữ nền giống Zalo lưu trữ). Nếu app hay bị dừng ở nền thì tắt mục này: app chạy ngầm chắc chắn hơn nhưng iOS sẽ hiện mũi tên.")
                }

                Section("Thông tin") {
                    LabeledContent("Phiên bản", value: AppSettings.versionText)
                }
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        if settings.isConfigured {
                            Task {
                                await store.refresh(settings: settings)
                            }
                        }
                        dismiss()
                    }
                    .fontWeight(.bold)
                }
            }
        }
        .sheet(isPresented: $access.showLogin) {
            let normalized = ServerAPI.normalizeBaseURL(settings.baseURL)
            let fallbackURL = URL(string: normalized)
            CloudflareLoginSheet(baseURL: access.loginURL ?? fallbackURL) {
                refreshExpiry.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: CloudflareAccess.didLoginNotification)) { _ in
            refreshExpiry.toggle()
        }
    }

    private func statusRow(ok: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(ok ? .green : .orange)
            Text(text).font(.footnote)
        }
    }

    private func testConnection() {
        isTesting = true
        statusMessage = nil
        isStatusSuccess = false

        let api = settings.makeAPI()
        Task {
            do {
                let count = try await api.listChats().count
                statusMessage = "Kết nối được, \(count) cuộc chat"
                isStatusSuccess = true
            } catch {
                statusMessage = error.localizedDescription
                isStatusSuccess = false
            }
            isTesting = false
        }
    }
}

struct BackgroundLogView: View {
    @State private var lines = BackgroundLog.lines

    var body: some View {
        List(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(line).font(.system(.footnote, design: .monospaced))
        }
        .overlay { if lines.isEmpty { Text("Chưa có").foregroundColor(.secondary) } }
        .navigationTitle("Nhật ký chạy ngầm")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { lines = BackgroundLog.lines }
    }
}
