//
//  Keychain.swift
//  ClaudeRemote
//
//  Luu tru an toan token xac thuc tren iOS Keychain su dung Security framework.
//

import Foundation
import Security

public enum Keychain {
    private static let service = "com.ducle.clauderemote"

    /// Luu chuoi gia tri vao Keychain cho mot key xac dinh.
    public static func set(_ v: String, for key: String) {
        guard let data = v.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // Xoa phan tu cu neu da ton tai truoc khi them moi
        SecItemDelete(query as CFDictionary)

        var newQuery = query
        newQuery[kSecValueData as String] = data
        // Doc duoc ca khi iPhone dang khoa man hinh (app chay nen). Mac dinh WhenUnlocked -> may khoa thi
        // doc ra nil, app tuong mat dang nhap Cloudflare va xoa cookie (v4.3)
        newQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(newQuery as CFDictionary, nil)
    }

    /// Lay chuoi gia tri tu Keychain theo key.
    public static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    /// Muc luu tu ban cu (WhenUnlocked) -> luu lai voi AfterFirstUnlock. Goi luc mo app (may dang mo khoa).
    public static func migrateAccessibility(keys: [String]) {
        let flag = "keychainAfterFirstUnlock"
        guard !UserDefaults.standard.bool(forKey: flag) else { return }
        for key in keys { if let v = get(key) { set(v, for: key) } }
        UserDefaults.standard.set(true, forKey: flag)
    }

    /// Xoa gia tri tu Keychain theo key.
    public static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
