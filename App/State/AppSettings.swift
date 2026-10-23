//
//  AppSettings.swift
//  ClaudeRemote
//
//  Quan ly cai dat may chu, ma xac thuc token va lich su thu muc lam viec gan day.
//

import Foundation
import Combine

public final class AppSettings: ObservableObject {
    private enum Keys {
        static let baseURL = "baseURL"
        static let recentDirs = "recentDirs"
        static let token = "token"
    }

    public static let defaultRecentDirs = ["C:\\Users\\ducle\\Code"]

    @Published public var baseURL: String {
        didSet {
            UserDefaults.standard.set(baseURL, forKey: Keys.baseURL)
        }
    }

    @Published public var token: String {
        didSet {
            if token.isEmpty {
                Keychain.delete(Keys.token)
            } else {
                Keychain.set(token, for: Keys.token)
            }
        }
    }

    @Published public var recentDirs: [String] {
        didSet {
            UserDefaults.standard.set(recentDirs, forKey: Keys.recentDirs)
        }
    }

    public init() {
        let defaultURL = "https://desktop-krdjkc2.tailbd558a.ts.net:8444"
        let oldDefaultURL = "https://desktop-krdjkc2.tailbd558a.ts.net:8443"
        var savedURL = UserDefaults.standard.string(forKey: Keys.baseURL)
        // Nguoi dung dang dung URL mac dinh cu (8443) thi tu chuyen sang 8444.
        if let saved = savedURL, saved.trimmingCharacters(in: CharacterSet(charactersIn: "/ \n")) == oldDefaultURL {
            savedURL = defaultURL
            UserDefaults.standard.set(defaultURL, forKey: Keys.baseURL)
        }
        self.baseURL = savedURL ?? defaultURL
        self.token = Keychain.get(Keys.token) ?? ""

        if let savedDirs = UserDefaults.standard.stringArray(forKey: Keys.recentDirs), !savedDirs.isEmpty {
            self.recentDirs = savedDirs
        } else {
            self.recentDirs = Self.defaultRecentDirs
        }
    }

    /// Kiem tra cau hinh da du baseURL va token chua.
    public var isConfigured: Bool {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedURL.isEmpty && !trimmedToken.isEmpty
    }

    /// Them mot duong dan thu muc vao danh sach gan day: moi nhat len dau, toi da 8 muc.
    public func addRecentDir(_ dir: String) {
        let trimmed = dir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var list = recentDirs.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        list.insert(trimmed, at: 0)
        if list.count > 8 {
            list = Array(list.prefix(8))
        }
        recentDirs = list
    }

    /// Khoi tao doi tuong ServerAPI voi cau hinh hien tai.
    public func makeAPI() -> ServerAPI {
        ServerAPI(baseURL: baseURL, token: token)
    }
}
