//
//  TerminalScreen.swift
//  ClaudeRemote
//
//  Man hinh terminal hien thi phien lam viec voi may chu.
//

import SwiftUI

struct TerminalScreen: View {
    let session: Session
    @EnvironmentObject var settings: AppSettings
    @State var state = TerminalConnection.State.connecting

    var body: some View {
        Group {
            if let url = settings.makeAPI().webSocketURL(sessionId: session.id) {
                ZStack {
                    Color.black
                        .ignoresSafeArea()

                    TerminalHost(url: url, state: $state, accessoryProvider: { tv, conn in KeyBar(terminalView: tv, connection: conn) })
                    // KHONG ignoresSafeArea(.keyboard) de ban phim day terminal len
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

            if !session.isRunning {
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
