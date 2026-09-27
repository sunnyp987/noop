import Foundation
import AuthenticationServices

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - WHOOP Cloud API — OAuth 2.0 + v2 data fetch
//
// Confidential-client OAuth per developer.whoop.com/docs/developing/oauth (fetched live, not
// guessed): the auth-code exchange AND every later refresh both need client_secret, so — unlike a
// pure-PKCE flow — the secret has to travel with the app. That's acceptable here only because this
// is a single-user BYO-credential tool (the user pastes their OWN client_id/secret from their OWN
// WHOOP Developer Dashboard app), never a shared embedded secret.
//
// "Seamless" per the user's ask: login happens in an ASWebAuthenticationSession sheet (stays inside
// the app, not a hand-off to Safari), the redirect is caught automatically via the `baseline-whoop`
// URL scheme already registered in Info.plist, and — because we request `offline` scope and store
// the rotating refresh_token — every sync after the FIRST login is silent. No re-auth prompt ever,
// unless the user explicitly disconnects or WHOOP revokes access.
enum WhoopCloudAPI {

    private static let authURL = "https://api.prod.whoop.com/oauth/oauth2/auth"
    private static let tokenURL = "https://api.prod.whoop.com/oauth/oauth2/token"
    private static let apiBase = "https://api.prod.whoop.com/developer/v2"
    private static let redirectURI = "baseline-whoop://oauth/callback"
    private static let scopes = "offline read:recovery read:cycles read:sleep read:profile read:body_measurement"

    enum WhoopCloudError: LocalizedError {
        case notConfigured
        case notConnected
        case authCancelled
        case authFailed(String)
        case network(String)
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Add your WHOOP Client ID and Secret first (from your own WHOOP Developer Dashboard app)."
            case .notConnected: return "Not connected to WHOOP yet — tap Connect."
            case .authCancelled: return "Sign-in was cancelled."
            case .authFailed(let m): return "WHOOP sign-in failed: \(m)"
            case .network(let m): return "Network error talking to WHOOP: \(m)"
            case .server(let code, let m): return "WHOOP API returned \(code): \(m)"
            }
        }
    }

    // MARK: - Sign-in

    /// Presents the WHOOP login sheet, exchanges the returned code for tokens, and stores them.
    /// After this completes once, `syncNow`-style calls never need to call this again.
    @MainActor
    static func connect() async throws {
        guard let clientId = WhoopCloudAuthStore.clientId, let clientSecret = WhoopCloudAuthStore.clientSecret,
              !clientId.isEmpty, !clientSecret.isEmpty else {
            throw WhoopCloudError.notConfigured
        }

        let state = randomState(length: 8)
        var comps = URLComponents(string: authURL)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "state", value: state),
        ]

        let callbackURL = try await webAuthSession(url: comps.url!, callbackScheme: "baseline-whoop")

        guard let callbackComps = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = callbackComps.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = callbackComps.queryItems?.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            throw WhoopCloudError.authFailed("missing or mismatched authorization code")
        }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = formEncode([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
        ])
        request.httpBody = body.data(using: .utf8)

        let token: WhoopCloud.TokenResponse = try await send(request)
        WhoopCloudAuthStore.saveTokens(access: token.accessToken, refresh: token.refreshToken, expiresIn: token.expiresIn)
    }

    static func disconnect() {
        WhoopCloudAuthStore.disconnect()
    }

    // MARK: - Silent refresh

    /// Ensures a valid access token, refreshing (and re-storing the rotated refresh token) if the
    /// current one has expired. Never prompts the user — this is the "auto-connect" path.
    ///
    /// A sync fires cycles/recoveries/sleep CONCURRENTLY (`async let` in WhoopCloudSyncScheduler), and
    /// each independently calls this. If the access token happens to be expired right when a sync
    /// starts, all three would otherwise race to refresh at once — but WHOOP rotates the refresh token
    /// on every use, so only ONE of three simultaneous refresh calls can succeed; the other two get
    /// rejected using an already-consumed token, and Swift's structured concurrency fails the WHOLE
    /// sync the instant any one of the three throws. That surfaced as a single opaque server error for
    /// the entire sync, even though one of the three silently succeeded underneath. `TokenRefreshGate`
    /// coalesces concurrent callers onto a single in-flight refresh instead of racing.
    private static func validAccessToken() async throws -> String {
        guard WhoopCloudAuthStore.isConnected else { throw WhoopCloudError.notConnected }

        if let token = WhoopCloudAuthStore.accessToken, let expiry = WhoopCloudAuthStore.accessTokenExpiresAt,
           expiry > Date() {
            return token
        }

        return try await TokenRefreshGate.shared.refreshedAccessToken()
    }

    fileprivate static func performTokenRefresh() async throws -> String {
        guard let refreshToken = WhoopCloudAuthStore.refreshToken,
              let clientId = WhoopCloudAuthStore.clientId, let clientSecret = WhoopCloudAuthStore.clientSecret else {
            throw WhoopCloudError.notConnected
        }

        var request = URLRequest(url: URL(string: tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = formEncode([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
            "client_secret": clientSecret,
            "scope": "offline",
        ])
        request.httpBody = body.data(using: .utf8)

        let token: WhoopCloud.TokenResponse = try await send(request)
        // WHOOP rotates the refresh token on every use — the old one is dead the instant this lands.
        WhoopCloudAuthStore.saveTokens(access: token.accessToken, refresh: token.refreshToken, expiresIn: token.expiresIn)
        return token.accessToken
    }

    // MARK: - Data fetch

    static func recentCycles(days: Int) async throws -> [WhoopCloud.Cycle] {
        try await paginatedGet(path: "/cycle", days: days)
    }

    static func recentRecoveries(days: Int) async throws -> [WhoopCloud.Recovery] {
        try await paginatedGet(path: "/recovery", days: days)
    }

    static func recentSleep(days: Int) async throws -> [WhoopCloud.SleepActivity] {
        try await paginatedGet(path: "/activity/sleep", days: days)
    }

    private static func paginatedGet<Record: Decodable>(path: String, days: Int) async throws -> [Record] {
        let accessToken = try await validAccessToken()
        let start = ISO8601DateFormatter().string(from: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date())

        var all: [Record] = []
        var nextToken: String?
        repeat {
            var comps = URLComponents(string: apiBase + path)!
            var items = [URLQueryItem(name: "limit", value: "25"), URLQueryItem(name: "start", value: start)]
            if let nextToken { items.append(.init(name: "nextToken", value: nextToken)) }
            comps.queryItems = items

            var request = URLRequest(url: comps.url!)
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let page: WhoopCloud.Page<Record> = try await send(request)
            all.append(contentsOf: page.records)
            nextToken = page.nextToken
        } while nextToken != nil

        return all
    }

    // MARK: - Networking helpers

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw WhoopCloudError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw WhoopCloudError.network("no response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WhoopCloudError.server(http.statusCode, body)
        }
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw WhoopCloudError.network("malformed response: \(error.localizedDescription)")
        }
    }

    private static func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let allowed = CharacterSet.urlQueryAllowed.subtracting(.init(charactersIn: "&=+"))
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(encodedValue)"
        }.joined(separator: "&")
    }

    private static func randomState(length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    // MARK: - ASWebAuthenticationSession bridge

    @MainActor
    private static func webAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: WhoopCloudError.authCancelled)
                } else {
                    continuation.resume(throwing: WhoopCloudError.authFailed(error?.localizedDescription ?? "unknown"))
                }
            }
            session.presentationContextProvider = WhoopCloudPresentationContext.shared
            // Keeping WHOOP's own login session (if the user is already signed into whoop.com in a
            // system browser context) is what makes repeat re-auth fast if it's ever needed again.
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }
}

/// Coalesces concurrent token-refresh callers onto a single in-flight network request. Actor isolation
/// serializes entry, so of any number of simultaneous callers, exactly one starts the real refresh and
/// every other one just awaits that same in-flight Task's result — never sends a second refresh_token
/// exchange that WHOOP would reject (it's already been rotated by the first).
private actor TokenRefreshGate {
    static let shared = TokenRefreshGate()
    private var inFlight: Task<String, Error>?

    func refreshedAccessToken() async throws -> String {
        // Re-check the cache: another caller may have completed a refresh while we were waiting to
        // enter this actor, in which case there's nothing left to do.
        if let token = WhoopCloudAuthStore.accessToken, let expiry = WhoopCloudAuthStore.accessTokenExpiresAt,
           expiry > Date() {
            return token
        }
        if let task = inFlight {
            return try await task.value
        }
        let task = Task { try await WhoopCloudAPI.performTokenRefresh() }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}

/// Minimal presentation anchor so ASWebAuthenticationSession has a window to present from.
private final class WhoopCloudPresentationContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WhoopCloudPresentationContext()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if os(iOS)
        let scene = UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
        let windowScene = scene as? UIWindowScene
        return windowScene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
        #elseif os(macOS)
        return NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
        #endif
    }
}
