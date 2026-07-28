import Foundation
import Security
import LocalAuthentication

/// Keychain-backed store for the long-lived session token.
///
/// The design doc's flow is: password (key) once → long-lived token → Face ID
/// from then on. So the token is the secret worth protecting, not the password,
/// and it is stored with `whenUnlockedThisDeviceOnly` — it must not ride an
/// iCloud backup to another device.
enum Keychain {
    private static let service = "link.hardcore.officraft"

    enum Item: String {
        case token = "session-token"
        case ownerId = "owner-id"
    }

    @discardableResult
    static func set(_ value: String, for item: Item) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ item: Item) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func remove(_ item: Item) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: item.rawValue,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    static func clearAll() {
        remove(.token)
        remove(.ownerId)
    }
}

// MARK: - Biometrics

/// Face ID / Touch ID gate in front of a stored token.
enum Biometrics {

    enum Kind {
        case faceID, touchID, none

        var label: String {
            switch self {
            case .faceID: return "Face ID"
            case .touchID: return "Touch ID"
            case .none: return "裝置密碼"
            }
        }
    }

    static var available: Kind {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .none
        }
    }

    /// Falls back to the device passcode so a failed face scan is not a dead end.
    static func authenticate(reason: String = "解鎖 OffiCraft 控制台") async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
        } catch {
            return false
        }
    }
}
