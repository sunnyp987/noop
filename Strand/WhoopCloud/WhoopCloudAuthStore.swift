import Foundation

// MARK: - WHOOP Cloud comparison tool — auth storage (Keychain)
//
// PRIVATE, NOT ADVERTISED (see WhoopCloudCompareView.swift's header for the full rationale): a
// personal validation tool for as long as an active WHOOP subscription exists, reachable only via
// a hidden gesture, never linked from primary navigation, never mentioned in CHANGELOG.md or the
// public AltStore source description. It exists to compare Baseline's own on-device-computed
// numbers against WHOOP's own cloud-computed numbers for the SAME underlying strap.
//
// BYO client credentials, same shape as AIKeyStore (AICoach.swift): the user creates their own
// OAuth app in the WHOOP Developer Dashboard (developer.whoop.com) and pastes the Client ID/Secret
// here. Nothing is embedded, nothing is shared across installs, and this is the ONLY place in the
// entire app that talks to a cloud service that isn't the user's own AI-provider key or the
// existing update checker.
enum WhoopCloudAuthStore {
    private static let service = "com.noop.whoopcloud"

    private enum Account: String {
        case clientId = "client-id"
        case clientSecret = "client-secret"
        case accessToken = "access-token"
        case refreshToken = "refresh-token"
    }

    private static func baseQuery(_ account: Account) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }

    private static func write(_ value: String?, _ account: Account) {
        let query = baseQuery(account)
        SecItemDelete(query as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    private static func read(_ account: Account) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let str = String(data: data, encoding: .utf8), !str.isEmpty else { return nil }
        return str
    }

    // MARK: - Client credentials (pasted once from the WHOOP Developer Dashboard)

    static var clientId: String? { read(.clientId) }
    static var clientSecret: String? { read(.clientSecret) }

    static func saveClientCredentials(id: String, secret: String) {
        write(id.trimmingCharacters(in: .whitespacesAndNewlines), .clientId)
        write(secret.trimmingCharacters(in: .whitespacesAndNewlines), .clientSecret)
    }

    // MARK: - Tokens (set after a completed OAuth login; refreshed silently thereafter)

    /// UserDefaults (non-secret) expiry epoch — the token VALUES live only in the Keychain.
    private static let expiresAtKey = "whoopCloud.accessTokenExpiresAt"

    static var accessToken: String? { read(.accessToken) }
    static var refreshToken: String? { read(.refreshToken) }
    static var accessTokenExpiresAt: Date? {
        let v = UserDefaults.standard.double(forKey: expiresAtKey)
        return v > 0 ? Date(timeIntervalSince1970: v) : nil
    }

    /// True once a login has completed and a refresh token is on hand — the "auto-connect" signal:
    /// as long as this is true, sync never needs to show a login screen again, only silently refresh.
    static var isConnected: Bool { refreshToken != nil }

    static func saveTokens(access: String, refresh: String, expiresIn: TimeInterval) {
        write(access, .accessToken)
        write(refresh, .refreshToken)
        // Refresh a little early (60s) so a sync never races an about-to-expire token.
        UserDefaults.standard.set(Date().addingTimeInterval(max(0, expiresIn - 60)).timeIntervalSince1970,
                                  forKey: expiresAtKey)
    }

    /// Disconnects (revokes locally — does not call WHOOP's revoke endpoint, so re-connecting later
    /// doesn't require creating a new OAuth app). Client credentials are left in place since they're
    /// not a secret about the USER, just the app registration.
    static func disconnect() {
        write(nil, .accessToken)
        write(nil, .refreshToken)
        UserDefaults.standard.removeObject(forKey: expiresAtKey)
    }
}
