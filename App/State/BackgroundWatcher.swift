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
    private static let hideArrowKey = "bgHideArrow"
    private static let interval: UInt64 = 4_000_000_000

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            enabled ? start() : stop()
        }
    }
    /// v3.8: an mui ten dinh vi canh camera (vi tri gan dung nhu Zalo luu tru). Tat = cach v3.7 (~3 km), chac giu nen hon
    @Published var hideArrow: Bool {
        didSet {
            UserDefaults.standard.set(hideArrow, forKey: Self.hideArrowKey)
            if enabled { applyAccuracy(); startLocation() }
        }
    }
    @Published private(set) var locationStatus: CLAuthorizationStatus
    /// "Vi tri chinh xac" dang bat trong Cai dat iPhone -> iOS luon hien mui ten, app khong tu tat duoc
    @Published private(set) var preciseLocation = false
    @Published private(set) var notifyAllowed = false
    /// Cham vao thong bao -> RootView mo chat nay
    @Published var pendingChatId: String?

    /// Chat dang mo tren man hinh: khong bao lai khi app dang mo dung chat do
    var openChatId: String?

    private let locationManager = CLLocationManager()
    private var makeAPI: (() -> ServerAPI?)?
    private var pollTask: Task<Void, Never>?
    private var seen: [String: (status: String, done: Int)] = [:]
    /// iOS 17+: phien chay nen chinh thuc (CLBackgroundActivitySession) - giu app chay khi o nen
    private var activitySession: AnyObject?

    private override init() {
        // Mac dinh BAT (giong Zalo luu tru): mo app la xin quyen thong bao + vi tri, chay ngam ngay
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        hideArrow = UserDefaults.standard.object(forKey: Self.hideArrowKey) as? Bool ?? true
        locationStatus = locationManager.authorizationStatus
        super.init()
        preciseLocation = locationManager.accuracyAuthorization == .fullAccuracy
        locationManager.delegate = self
        applyAccuracy()
        locationManager.activityType = .other
        locationManager.pausesLocationUpdatesAutomatically = false
        UNUserNotificationCenter.current().delegate = self
        // Giong Zalo luu tru: moi lan ra nen thi bat lai theo doi vi tri
        NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            BackgroundLog.add("Ra nền")
            BackgroundLog.markEnteredBackground()
            Task { @MainActor in
                let w = BackgroundWatcher.shared
                if w.enabled { w.startLocation() }
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            BackgroundLog.add("Vào lại app")
            BackgroundLog.clearBackgroundMark()
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            BackgroundLog.add("iOS báo thiếu bộ nhớ")
        }
        // Vuot tat app dang chay o nen -> iOS goi willTerminate: bao ngay
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            BackgroundLog.add("App bị tắt (vuốt khỏi đa nhiệm)")
            if UserDefaults.standard.object(forKey: "bgNotify") as? Bool ?? true { KilledNotice.shared.fireNow() }
        }
    }

    /// Goi 1 lan luc mo app (ke ca khi iOS mo lai app o nen vi doi vi tri)
    func configure(makeAPI: @escaping () -> ServerAPI?) {
        self.makeAPI = makeAPI
        BackgroundLog.reportPreviousRun()
        if enabled { start() }
    }

    var keepsAlive: Bool { locationStatus == .authorizedAlways }

    private func start() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
            Task { @MainActor in self.notifyAllowed = ok }
        }
        switch locationManager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            // Dang "Khi dung app" -> iOS hoi nang len "Luon luon" (chi hoi 1 lan)
            locationManager.requestAlwaysAuthorization()
        default:
            break
        }
        startLocation()
        KilledNotice.shared.start()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                BackgroundLog.heartbeat()
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
        if #available(iOS 17.0, *) { (activitySession as? CLBackgroundActivitySession)?.invalidate() }
        activitySession = nil
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.allowsBackgroundLocationUpdates = false
    }

    /// An mui ten: dung y cau hinh Zalo luu tru v4.0 (vi tri gan dung + distanceFilter toi da, iOS gan nhu
    /// khong gui vi tri nen khong hien mui ten). v3.8 de distanceFilter None -> iOS gui vi tri lien tuc, mui ten
    /// van hien. Giu nen van nho CLBackgroundActivitySession. Khong an: ~3 km + moi cap nhat nhu v3.7.
    private func applyAccuracy() {
        locationManager.desiredAccuracy = hideArrow ? kCLLocationAccuracyReduced : kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = hideArrow ? CLLocationDistanceMax : kCLDistanceFilterNone
    }

    fileprivate func startLocation() {
        let st = locationManager.authorizationStatus
        guard st == .authorizedAlways || st == .authorizedWhenInUse else { return }
        let always = st == .authorizedAlways
        locationManager.allowsBackgroundLocationUpdates = true
        // "Luon luon": an vien xanh giong Zalo luu tru. "Khi dung app": iOS bat buoc hien vien xanh,
        // an di thi iOS dung cap nhat vi tri o nen -> app bi treo sau ~30s
        locationManager.showsBackgroundLocationIndicator = !always
        locationManager.startUpdatingLocation()
        // iOS 17+: phien nen chinh thuc cua Apple - giu app song chac nhat, NHUNG iOS hien mui ten xanh trong
        // Dynamic Island suot luc app o nen (video nguoi dung 28/10/2026, ca v3.7-3.9). An mui ten -> bo phien,
        // giu nen chi bang vi tri dung y Zalo luu tru
        if #available(iOS 17.0, *) {
            if hideArrow {
                (activitySession as? CLBackgroundActivitySession)?.invalidate()
                activitySession = nil
            } else if activitySession == nil {
                activitySession = CLBackgroundActivitySession()
            }
        }
        // App bi iOS tat han -> iOS mo lai app o nen khi vi tri doi dang ke (~500 m).
        // Theo doi nay lam iOS hien mui ten rong -> chi bat khi khong an mui ten
        if always && !hideArrow { locationManager.startMonitoringSignificantLocationChanges() }
        else { locationManager.stopMonitoringSignificantLocationChanges() }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    // MARK: - Hoi server

    private func poll() async {
        guard let api = makeAPI?() else { return }
        let active = UIApplication.shared.applicationState == .active
        let inBackground = UIApplication.shared.applicationState == .background
        let chats: [ChatMeta]
        do {
            chats = try await api.listChats()
            if inBackground { BackgroundLog.add("Ở nền: hỏi server OK", throttle: 60) }
        } catch {
            if inBackground { BackgroundLog.add("Ở nền: lỗi hỏi server - \(error.localizedDescription)", throttle: 60) }
            return
        }
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
            preciseLocation = manager.accuracyAuthorization == .fullAccuracy
            if enabled { startLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        BackgroundLog.add("Nhận vị trí", throttle: 120)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        BackgroundLog.add("Lỗi vị trí: \(error.localizedDescription)", throttle: 120)
    }
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

/// Bao "app da ngung chay":
/// - Vuot tat khi app dang chay o nen: willTerminate -> fireNow() hien sau 1s.
/// - Luoi an toan (app bi iOS dung / chet that): cu 20s hen lai 1 thong bao sau 90s cung ma. Truoc la 5s/6s
///   (giong Zalo luu tru) nhung iOS lam tre dong ho cua app yen lang o nen -> bao sai du app van song.
final class KilledNotice {
    static let shared = KilledNotice()
    private let id = "clauderemote.app-da-ngung-chay"
    private let every: TimeInterval = 20
    private let after: TimeInterval = 90
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

    /// Goi trong willTerminate: cho toi 1s de iOS nhan hen truoc khi app chet
    func fireNow() {
        let done = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request(after: 1)) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 1)
    }

    private func request(after seconds: TimeInterval) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Claude Remote đã ngừng chạy"
        content.body = "Chạm để mở lại, nếu không sẽ không nhận được thông báo khi Claude / agy làm xong."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private func schedule() {
        guard running else { return }
        UNUserNotificationCenter.current().add(request(after: after))
        queue.asyncAfter(deadline: .now() + every) { [weak self] in self?.schedule() }
    }
}

/// Nhat ky chay ngam (60 dong cuoi) - xem trong Cai dat de biet app co con song o nen khong
enum BackgroundLog {
    private static let key = "bgLog"
    private static let lock = NSLock()
    private static var lastByText: [String: Date] = [:]

    static func add(_ text: String, throttle: TimeInterval = 0) {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        if throttle > 0, let last = lastByText[text], now.timeIntervalSince(last) < throttle { return }
        lastByText[text] = now
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss dd/MM"
        var lines = UserDefaults.standard.stringArray(forKey: key) ?? []
        lines.append("\(f.string(from: now))  \(text)")
        UserDefaults.standard.set(Array(lines.suffix(60)), forKey: key)
    }

    static var lines: [String] { (UserDefaults.standard.stringArray(forKey: key) ?? []).reversed() }

    // "Con song" moi vong hoi server (~4s): mo lai app thi biet lan truoc song o nen duoc bao lau
    private static let enteredKey = "bgEnteredAt"
    private static let aliveKey = "bgAliveAt"

    static func markEnteredBackground() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: enteredKey)
        heartbeat()
    }

    static func clearBackgroundMark() {
        report(prefix: "Lần ở nền vừa rồi")
        UserDefaults.standard.removeObject(forKey: enteredKey)
    }

    static func heartbeat() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: aliveKey)
    }

    /// Goi luc mo app: lan truoc app chet khi dang o nen -> ghi song duoc bao lau
    static func reportPreviousRun() {
        report(prefix: "Lần trước app dừng")
        UserDefaults.standard.removeObject(forKey: enteredKey)
    }

    private static func report(prefix: String) {
        let d = UserDefaults.standard
        guard let entered = d.object(forKey: enteredKey) as? Double, let alive = d.object(forKey: aliveKey) as? Double else { return }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let secs = Int(max(0, alive - entered))
        add("\(prefix): ra nền \(f.string(from: Date(timeIntervalSince1970: entered))), còn chạy tới \(f.string(from: Date(timeIntervalSince1970: alive))) (\(secs) giây)")
    }
}
