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

    @State private var isTesting: Bool = false
    @State private var statusMessage: String? = nil
    @State private var isStatusSuccess: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                Section("URL máy chủ") {
                    TextField("https://desktop-krdjkc2.tailbd558a.ts.net:8444", text: $settings.baseURL)
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

                Section {
                    Toggle("Chạy ngầm & báo khi xong", isOn: $watcher.enabled)
                    if watcher.enabled {
                        statusRow(ok: watcher.keepsAlive,
                                  text: watcher.keepsAlive ? "Vị trí: Luôn luôn — app chạy ngầm được" : "Vị trí chưa đặt \"Luôn luôn\" — vào Cài đặt iPhone › Claude Remote › Vị trí để đổi")
                        statusRow(ok: watcher.notifyAllowed,
                                  text: watcher.notifyAllowed ? "Đã cho phép thông báo" : "Chưa cho phép thông báo")
                        Toggle("Ẩn mũi tên định vị", isOn: $watcher.hideArrow)
                        NavigationLink("Nhật ký chạy ngầm") { BackgroundLogView() }
                        if !watcher.keepsAlive || !watcher.notifyAllowed {
                            Button("Mở Cài đặt iPhone") { watcher.openSettings() }
                        }
                    }
                } header: {
                    Text("Thông báo")
                } footer: {
                    Text("Báo khi Claude / agy làm xong hoặc cần bạn trả lời, kể cả khi bạn đang dùng app khác. App dùng quyền vị trí (độ chính xác thấp, không gửi đi đâu) chỉ để iOS cho chạy ngầm, giống app Clip. Nếu app bị vuốt tắt sẽ có thông báo nhắc mở lại app. \"Ẩn mũi tên định vị\": dùng vị trí gần đúng để không hiện mũi tên cạnh camera; nếu app hay bị dừng ở nền thì tắt mục này.")
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
