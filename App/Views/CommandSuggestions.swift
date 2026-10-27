//
//  CommandSuggestions.swift
//  ClaudeRemote
//
//  Goi y lenh "/" tren o nhap: go "/" hien danh sach, go tiep de loc, cham de dien vao o nhap.
//

import SwiftUI

struct CommandSuggestions: View {
    let commands: [SlashCommand]
    let onPick: (SlashCommand) -> Void

    private let rowHeight: CGFloat = 50

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(commands) { cmd in
                    Button {
                        onPick(cmd)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: cmd.skill == true ? "sparkles" : "command")
                                .font(.footnote)
                                .foregroundColor(.claudeAccent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("/" + cmd.name)
                                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                Text(cmd.desc)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if cmd.id != commands.last?.id {
                        Divider().padding(.leading, 42)
                    }
                }
            }
        }
        .frame(height: min(CGFloat(commands.count) * rowHeight, rowHeight * 5.5))
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08)))
    }
}
