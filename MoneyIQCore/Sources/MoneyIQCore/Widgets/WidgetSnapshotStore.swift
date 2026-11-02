import Foundation
import Security

/// A small encrypted snapshot shared by the app and widget extension using
/// their common Keychain access group. This works with the personal team's
/// profiles, unlike App Group containers. Each target supplies the signed
/// group identifier through its Info.plist.
public enum WidgetSnapshotStore {
    private static let service = "com.moneyiq.widget-snapshot"
    private static let account = "current"
    private static let groupInfoKey = "MIQ_WIDGET_KEYCHAIN_GROUP"

    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: groupInfoKey) as? String
    }

    private static func query(group: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group
        ]
    }

    public static func load() -> WidgetSnapshot? {
        guard let group = accessGroup else { return nil }
        var request = query(group: group)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    public static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let group = accessGroup,
              let data = try? JSONEncoder().encode(snapshot) else { return false }
        let request = query(group: group)
        let status = SecItemUpdate(request as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var newItem = request
        newItem[kSecValueData as String] = data
        newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(newItem as CFDictionary, nil) == errSecSuccess
    }

    public static func clear() {
        guard let group = accessGroup else { return }
        SecItemDelete(query(group: group) as CFDictionary)
    }
}
