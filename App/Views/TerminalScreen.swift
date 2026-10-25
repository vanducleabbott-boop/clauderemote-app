//
//  TerminalScreen.swift
//  ClaudeRemote
//
//  Man hinh terminal hien thi phien lam viec voi may chu.
//

import SwiftUI

struct TerminalScreen: View {
    let session: Session
    /// Phien khong con tren server: chi xem lich su luu tren may
    var readOnly: Bool = false
    @EnvironmentObject var settings: AppSettings
    @State var state = TerminalConnection.State.connecting

    enum Tab: Hashable {
        case terminal
        case files
    }
    @State private var tab: Tab = .terminal

    var body: some View {
        Group {
            if readOnly || settings.makeAPI().webSocketURL(sessionId: session.id) != nil {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    // Terminal luon giu trong cay view (an khi o tab File) de khong mat ket noi
                    TerminalHost(session: session,
                                 url: readOnly ? nil : settings.makeAPI().webSocketURL(sessionId: session.id),
                                 state: $state,
                                 accessoryProvider: { tv, conn in KeyBar(terminalView: tv, connection: conn) })
                        .opacity(tab == .terminal ? 1 : 0)
                        .allowsHitTesting(tab == .terminal)
                    // KHONG ignoresSafeArea(.keyboard) de ban phim day terminal len

                    if tab == .files {
                        SessionFilesView(session: session)
                            .background(Color(.systemGroupedBackground))
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if !readOnly {
                        Picker("", selection: $tab) {
                            Text("Terminal").tag(Tab.terminal)
                            Text("File").tag(Tab.files)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black)
                    }
                }
                .onChange(of: tab) { newTab in
                    if newTab == .files {
                        // Cat ban phim terminal khi sang tab File
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            } else {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    Text("Không tạo được địa chỉ kết nối")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbarView
            }
        }
    }

    @ViewBuilder
    private var trailingToolbarView: some View {
        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 5) {
                Circle()
                    .fill(statusIndicatorColor)
                    .frame(width: 7, height: 7)

                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if readOnly {
                Text("Lịch sử trên máy")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else if !session.isRunning {
                Text("Phiên đã thoát")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var statusIndicatorColor: Color {
        switch state {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .disconnected:
            return .red
        }
    }

    private var statusText: String {
        switch state {
        case .connected:
            return "Đã kết nối"
        case .connecting:
            return "Đang kết nối…"
        case .disconnected(let reason):
            if let reason = reason, !reason.isEmpty {
                let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count > 20 {
                    let shortReason = String(trimmed.prefix(20))
                    return "Mất kết nối (\(shortReason)…)"
                }
                return "Mất kết nối (\(trimmed))"
            }
            return "Mất kết nối"
        }
    }
}
