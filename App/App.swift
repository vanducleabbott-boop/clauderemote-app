//
//  App.swift
//  ClaudeRemote
//

import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Chay ca khi iOS mo app o nen (doi vi tri) - luc do chua co man hinh SwiftUI
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let bg = launchOptions?[.location] != nil ? " (iOS mở lại ở nền do vị trí)" : ""
        BackgroundLog.add("Mở app" + bg)
        // Ban cu luu token + cookie Cloudflare chi doc duoc khi may mo khoa -> chuyen sang doc duoc ca khi khoa
        if application.isProtectedDataAvailable {
            Keychain.migrateAccessibility(keys: ["token", CloudflareAccess.cookieKey, CloudflareAccess.expKey])
        }
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
