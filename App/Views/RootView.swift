//
//  RootView.swift
//  ClaudeRemote
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showSettings: Bool = false

    var body: some View {
        NavigationStack {
            SessionListView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            if !settings.isConfigured {
                showSettings = true
            }
        }
    }
}
