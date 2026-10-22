//
//  NewSessionView.swift
//  ClaudeRemote
//

import SwiftUI

struct NewSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: SessionStore

    @State private var name: String = ""
    @State private var cwd: String = ""
    @State private var tool: String = "claude"     // "claude" | "agy"
    @State private var mode: String = "normal"     // "normal" | "skip"
    @State private var openTab: Bool = true
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil

    private var isFormValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && !trimmedCwd.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tên phiên") {
                    TextField("Tên phiên", text: $name)
                        .autocorrectionDisabled(true)
                }

                Section("Thư mục") {
                    TextField("C:\\Users\\ducle\\Code", text: $cwd)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)

                    if !settings.recentDirs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Thư mục gần đây")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(settings.recentDirs, id: \.self) { dir in
                                        Button {
                                            cwd = dir
                                        } label: {
                                            Text(dir)
                                                .font(.caption)
                                                .lineLimit(1)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(cwd == dir ? Color.blue.opacity(0.3) : Color.gray.opacity(0.2))
                                                .foregroundColor(cwd == dir ? Color.blue : Color.primary)
                                                .cornerRadius(6)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Section("Cấu hình công cụ") {
                    Picker("Loại", selection: $tool) {
                        Text("claude").tag("claude")
                        Text("agy").tag("agy")
                    }
                    .pickerStyle(.segmented)

                    if tool == "claude" {
                        Picker("Chế độ quyền", selection: $mode) {
                            Text("Thường").tag("normal")
                            Text("Bỏ qua hỏi quyền").tag("skip")
                        }
                    } else {
                        HStack {
                            Text("Chế độ quyền")
                            Spacer()
                            Text("agy luôn chạy full quyền")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    Toggle("Mở tab trên PC", isOn: $openTab)
                }

                if let errorMessage = errorMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundColor(.red)
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Tạo phiên mới")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Hủy") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Tạo") {
                        createSession()
                    }
                    .fontWeight(.bold)
                    .disabled(!isFormValid)
                }
            }
            .onAppear {
                if cwd.isEmpty {
                    cwd = settings.recentDirs.first ?? "C:\\Users\\ducle\\Code"
                }
            }
        }
    }

    private func createSession() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedCwd.isEmpty, !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil

        let chosenMode = (tool == "agy") ? "skip" : mode
        let request = NewSessionRequest(
            cwd: trimmedCwd,
            name: trimmedName,
            mode: chosenMode,
            tool: tool,
            openTab: openTab
        )

        Task {
            do {
                _ = try await settings.makeAPI().createSession(request)
                settings.addRecentDir(trimmedCwd)
                await store.refresh(settings: settings)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
