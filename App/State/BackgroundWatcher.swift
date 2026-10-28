//
//  BackgroundWatcher.swift
//  ClaudeRemote
//
//  Chay ngam + thong bao khi phien xong. Khong co push cua Apple (cai bang ESign) nen giu app
//  song bang vi tri "Luon luon" do chinh xac thap (cach cua Clip), roi hoi server vai giay mot lan.
//

import Foundation
import CoreLocation
import UserNotifications
import UIKit

@MainActor
final class BackgroundWatcher: NSObject, ObservableObject {
    static let shared = BackgroundWatcher()

    private static let enabledKey = "bgNotify"
    private static let interval: UInt64 = 4_000_000_000

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            enabled ? start() : stop()
        }
    }
    @Published private(set) var locationStatus: CLAuthorizationStatus
    @Published private(set) var notifyAllowed = false
    /// Cham vao thong bao -> RootView mo chat nay
    @Published var pendingChatId: String?

    /// Chat dang mo tren man hinh: khong bao lai khi app dang mo dung chat do
    var openChatId: String?

    private let locationManager = CLLocationManager()
    private var makeAPI: (() -> ServerAPI?)?
    private var pollTask: Task<Void, Never>?
    private var seen: [String: (status: String, done: Int)] = [:]

    private override init() {
        // Mac dinh BAT (giong Zalo luu tru): mo app la xin quyen thong bao + vi tri, chay ngam ngay
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        locationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        // Giong Zalo luu tru (ViTriGiuNen) + Clip: vi tri gan dung, khong bat GPS, khong hien mui ten.
        // Chay tot tren iPhone that; may ao thi van cho app ngu sau ~30s.
        locationManager.desiredAccuracy = kCLLocationAccuracyReduced
        locationManager.distanceFilter = CLLocationDistanceMax
        locationManager.activityType = .other
        locationManager.pausesLocationUpdatesAutomatically = false
        UNUserNotificationCenter.current().delegate = self
        // Giong Zalo luu tru: moi lan ra nen thi bat lai theo doi vi tri
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                let w = BackgroundWatcher.shared
                if w.enabled { w.startLocation() }
            }
        }
    }

    /// Goi 1 lan luc mo app (ke ca khi iOS mo lai app o nen vi doi vi tri)
    func configure(makeAPI: @escaping () -> ServerAPI?) {
        self.makeAPI = makeAPI
        if enabled { start() }
    }

    var keepsAlive: Bool { locationStatus == .authorizedAlways }

    private func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            Task { @MainActor in self.notifyAllowed = ok }
        }
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
        startLocation()
        KilledNotice.shared.start()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: Self.interval)
            }
        }
    }

    private func stop() {
        pollTask?.cancel()
        pollTask = nil
        seen = [:]
        KilledNotice.shared.stop()
        locationManager.stopUpdatingLocation()
        locationManager.allowsBackgroundLocationUpdates = false
    }

    fileprivate func startLocation() {
        let st = locationManager.authorizationStatus
        guard st == .authorizedAlways || st == .authorizedWhenInUse else { return }
        locationManager.allowsBackgroundLocationUpdates = true
        // Quyen "Luon luon" thi iOS khong hien vien xanh bao dung vi tri o nen
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.startUpdatingLocation()
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: - Hoi server

    private func poll() async {
        guard let api = makeAPI?() else { return }
        guard let chats = try? await api.listChats() else { return }
        let active = UIApplication.shared.applicationState == .active
        for c in chats {
            let done = c.turnsDone ?? 0
            defer { seen[c.id] = (c.status, done) }
            guard let prev = seen[c.id] else { continue }
            if active && c.id == openChatId { continue }
            if c.status == "idle" && done > prev.done {
                notify(c, waiting: false)
            } else if c.status == "waiting" && prev.status != "waiting" {
                notify(c, waiting: true)
            }
        }
    }

    private func notify(_ c: ChatMeta, waiting: Bool) {
        let content = UNMutableNotificationContent()
        content.title = waiting ? "\(c.toolName) cần bạn trả lời" : "\(c.toolName) đã xong"
        content.subtitle = c.name
        var body = waiting ? "Đang chờ bạn cho phép hoặc chọn câu trả lời." : (c.preview ?? "")
        if !waiting, let n = c.lastFiles, n > 0 { body = "📎 \(n) file kết quả · " + body }
        content.body = body
        content.sound = .default
        content.threadIdentifier = c.id
        content.userInfo = ["chatId": c.id]
        let req = UNNotificationRequest(identifier: "\(c.id)-\(c.turnsDone ?? 0)-\(waiting)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

extension BackgroundWatcher: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            locationStatus = manager.authorizationStatus
            if enabled { startLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension BackgroundWatcher: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.content.userInfo["chatId"] as? String
        Task { @MainActor in
            if let id { pendingChatId = id }
            completionHandler()
        }
    }
}

/// Bao "app da ngung chay" - meo cua Clip / Zalo luu tru (BaoAppDaTat): cu 5s hen lai 1 thong bao sau 6s cung ma
/// -> app con song thi khong bao gio kip hien; app bi vuot tat thi khong ai hen lai -> 6s sau hien, cham la mo lai.
/// Chay tren luong nen (khong phai luong chinh) giong Zalo luu tru.
final class KilledNotice {
    static let shared = KilledNotice()
    private let id = "clauderemote.app-da-ngung-chay"
    private let every: TimeInterval = 5
    private let queue = DispatchQueue(label: "clauderemote.killed-notice")
    private var running = false

    func start() {
        queue.async {
            guard !self.running else { return }
            self.running = true
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [self.id])
            self.schedule()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [self.id])
        }
    }

    private func schedule() {
        guard running else { return }
        let content = UNMutableNotificationContent()
        content.title = "Claude Remote đã ngừng chạy"
        content.body = "Chạm để mở lại, nếu không sẽ không nhận được thông báo khi Claude / agy làm xong."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: every + 1, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        queue.asyncAfter(deadline: .now() + every) { [weak self] in self?.schedule() }
    }
}
