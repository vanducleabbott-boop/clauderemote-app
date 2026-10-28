//
//  App.swift
//  ClaudeRemote
//

import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Chay ca khi iOS mo app o nen (doi vi tri) - luc do chua co man hinh SwiftUI
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundWatcher.shared.configure {
            let s = AppSettings()
            return s.isConfigured ? s.makeAPI() : nil
        }
        return true
    }
}

@main
struct ClaudeRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
