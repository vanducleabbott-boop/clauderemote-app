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
    /// Bao "app da ngung chay" (meo cua Clip / Zalo luu tru)
    private static let killedNoticeId = "clauderemote.app-da-ngung-chay"
    private static let killedNoticeEvery: TimeInterval = 5
    private var killedNoticeOn = false

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
        startKilledNotice()
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
        killedNoticeOn = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.killedNoticeId])
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.allowsBackgroundLocationUpdates = false
    }

    private func startLocation() {
        let st = locationManager.authorizationStatus
        guard st == .authorizedAlways || st == .authorizedWhenInUse else { return }
        locationManager.allowsBackgroundLocationUpdates = true
        // Quyen "Luon luon" thi iOS khong hien vien xanh bao dung vi tri o nen
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.startUpdatingLocation()
        // iOS tu mo lai app o nen khi di chuyen xa (neu app bi he thong tat)
        locationManager.startMonitoringSignificantLocationChanges()
    }

    /// Cu 5s hen lai 1 thong bao sau 6s cung ma -> app con song thi khong bao gio hien;
    /// app bi vuot tat / iOS dung thi khong ai hen lai -> 6s sau hien, cham vao la mo lai app
    private func startKilledNotice() {
        guard !killedNoticeOn else { return }
        killedNoticeOn = true
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.killedNoticeId])
        scheduleKilledNotice()
    }

    private func scheduleKilledNotice() {
        guard killedNoticeOn else { return }
        let content = UNMutableNotificationContent()
        content.title = "Claude Remote đã ngừng chạy"
        content.body = "Chạm để mở lại, nếu không sẽ không nhận được thông báo khi Claude / agy làm xong."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Self.killedNoticeEvery + 1, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.killedNoticeId, content: content, trigger: trigger))
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.killedNoticeEvery) { [weak self] in self?.scheduleKilledNotice() }
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
