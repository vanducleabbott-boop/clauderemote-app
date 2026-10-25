//
//  SettingsView.swift
//  ClaudeRemote
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: SessionStore

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

    private func testConnection() {
        isTesting = true
        statusMessage = nil
        isStatusSuccess = false

        let api = settings.makeAPI()
        Task {
            do {
                let count = try await api.checkConnection()
                statusMessage = "Kết nối được, \(count) phiên"
                isStatusSuccess = true
            } catch {
                statusMessage = error.localizedDescription
                isStatusSuccess = false
            }
            isTesting = false
        }
    }
}
