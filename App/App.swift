//
//  App.swift
//  ClaudeRemote
//

import SwiftUI

@main
struct ClaudeRemoteApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = ChatStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
