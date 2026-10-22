//
//  App.swift
//  ClaudeRemote
//

import SwiftUI

@main
struct ClaudeRemoteApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
