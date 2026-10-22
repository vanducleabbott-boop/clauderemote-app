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
