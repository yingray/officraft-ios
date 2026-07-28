import SwiftUI
import Observation

/// Connection + auth state for the whole app.
///
/// The design doc's flow: the server binds loopback, so the app must be told a
/// host first; the owner password (key) is exchanged once for a long-lived
/// token, and every later launch unlocks with Face ID.
@Observable
final class AppSession {

    enum Phase: Equatable {
        case loading
        /// No stored token — show 連到你的工作室.
        case signedOut
        /// Token present but the biometric gate has not been passed yet.
        case locked
        case signedIn
        /// Browsing the design doc's sample studio without a server.
        case demo
    }

    enum Reachability: Equatable {
        case unknown
        case connected(latencyMs: Int)
        case failed(String)

        var label: String {
            switch self {
            case .unknown: return "未測試"
            case .connected(let ms): return "已連線 · \(ms) ms"
            case .failed: return "連不上"
            }
        }

        var tint: Color {
            switch self {
            case .unknown: return OC.labelTertiary
            case .connected: return OC.accent
            case .failed: return OC.danger
            }
        }
    }

    private(set) var phase: Phase = .loading
    private(set) var reachability: Reachability = .unknown
    private(set) var ownerId: String = "owner"
    private(set) var serverVersion: String?

    /// Saved connection targets — 本機 / tunnel / VPN, switched in one tap.
    var hosts: [ServerHost] = []
    var activeHostID: UUID?

    /// Preferences that live on the device, not the server.
    var useBiometrics: Bool = true
    var rememberDevice: Bool = true
    var appearance: AppearancePreference = .system
    var askPushEnabled: Bool = true
    var taskDonePushEnabled: Bool = false
    var lockScreenDetail: LockScreenDetail = .summary

    let api = APIClient()
    let events = EventStream()

    var activeHost: ServerHost? {
        guard let activeHostID else { return hosts.first }
        return hosts.first { $0.id == activeHostID } ?? hosts.first
    }

    var isDemo: Bool { phase == .demo }

    // MARK: - Lifecycle

    func bootstrap() async {
        loadPreferences()

        guard let host = activeHost, let token = Keychain.get(.token) else {
            phase = .signedOut
            return
        }
        ownerId = Keychain.get(.ownerId) ?? "owner"
        await api.configure(host: host, token: token)

        // A stored token still needs the biometric gate when it is switched on.
        if useBiometrics, Biometrics.available != .none {
            phase = .locked
        } else {
            phase = .signedIn
            startEvents()
        }
    }

    /// Face ID / passcode gate in front of an existing token.
    func unlock() async -> Bool {
        guard phase == .locked else { return phase == .signedIn }
        let ok = await Biometrics.authenticate()
        if ok {
            phase = .signedIn
            startEvents()
        }
        return ok
    }

    func signIn(host rawHost: String, password: String, remember: Bool) async throws {
        let trimmed = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw APIError.badHost(trimmed) }

        // Reuse the saved entry when the owner re-enters a known host, so
        // switching back does not accumulate duplicates.
        let host: ServerHost
        if let existing = hosts.first(where: { $0.display == ServerHost(raw: trimmed).display }) {
            host = existing
        } else {
            host = ServerHost(raw: trimmed, label: ServerHost(raw: trimmed).display)
            hosts.append(host)
        }
        activeHostID = host.id

        await api.configure(host: host, token: nil)
        let response = try await api.login(password: password)

        ownerId = response.ownerId
        rememberDevice = remember
        await api.configure(host: host, token: response.token)

        if remember {
            Keychain.set(response.token, for: .token)
            Keychain.set(response.ownerId, for: .ownerId)
        } else {
            Keychain.clearAll()
        }
        savePreferences()

        phase = .signedIn
        reachability = .connected(latencyMs: 0)
        startEvents()
        await refreshVersion()
    }

    func enterDemo() {
        phase = .demo
    }

    func signOut() {
        Keychain.clearAll()
        Task { await events.disconnect() }
        Task { await api.configure(host: activeHost, token: nil) }
        phase = .signedOut
        reachability = .unknown
    }

    // MARK: - Connection

    /// 測試連線 — round-trips `/api/health` and reports the latency the
    /// settings screen shows next to the status dot.
    @discardableResult
    func testConnection() async -> Reachability {
        guard !isDemo else {
            reachability = .connected(latencyMs: 12)
            return reachability
        }
        let started = Date()
        do {
            try await api.health()
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            reachability = .connected(latencyMs: ms)
        } catch {
            reachability = .failed((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
        return reachability
    }

    func switchHost(to host: ServerHost) async {
        activeHostID = host.id
        savePreferences()
        await api.configure(host: host, token: Keychain.get(.token))
        await testConnection()
        startEvents()
    }

    private func refreshVersion() async {
        serverVersion = try? await api.version().version
    }

    private func startEvents() {
        guard let host = activeHost, let token = Keychain.get(.token) else { return }
        Task { await events.connect(host: host, token: token) }
    }

    /// Called when any request comes back 401 — the token expired or was
    /// revoked by a password change on another device.
    func handleUnauthorized() {
        Keychain.remove(.token)
        Task { await events.disconnect() }
        phase = .signedOut
    }

    // MARK: - Preferences

    private enum Key {
        static let hosts = "oc.hosts"
        static let activeHost = "oc.activeHost"
        static let biometrics = "oc.useBiometrics"
        static let appearance = "oc.appearance"
        static let askPush = "oc.push.ask"
        static let taskPush = "oc.push.taskDone"
        static let lockDetail = "oc.push.lockDetail"
    }

    func savePreferences() {
        let defaults = UserDefaults.standard
        if let encoded = try? JSONEncoder().encode(hosts) {
            defaults.set(encoded, forKey: Key.hosts)
        }
        defaults.set(activeHostID?.uuidString, forKey: Key.activeHost)
        defaults.set(useBiometrics, forKey: Key.biometrics)
        defaults.set(appearance.rawValue, forKey: Key.appearance)
        defaults.set(askPushEnabled, forKey: Key.askPush)
        defaults.set(taskDonePushEnabled, forKey: Key.taskPush)
        defaults.set(lockScreenDetail.rawValue, forKey: Key.lockDetail)
    }

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Key.hosts),
           let decoded = try? JSONDecoder().decode([ServerHost].self, from: data) {
            hosts = decoded
        }
        if let raw = defaults.string(forKey: Key.activeHost) {
            activeHostID = UUID(uuidString: raw)
        }
        useBiometrics = defaults.object(forKey: Key.biometrics) as? Bool ?? true
        appearance = AppearancePreference(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        askPushEnabled = defaults.object(forKey: Key.askPush) as? Bool ?? true
        taskDonePushEnabled = defaults.object(forKey: Key.taskPush) as? Bool ?? false
        lockScreenDetail = LockScreenDetail(rawValue: defaults.string(forKey: Key.lockDetail) ?? "") ?? .summary
    }
}

// MARK: - Preference types

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟隨系統"
        case .light: return "淺色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 鎖定畫面顯示選項 — how much of a reply card the Lock Screen may reveal.
enum LockScreenDetail: String, CaseIterable, Identifiable {
    case summary, full, hidden
    var id: String { rawValue }

    var label: String {
        switch self {
        case .summary: return "摘要"
        case .full: return "完整問題與選項"
        case .hidden: return "只顯示有新請示"
        }
    }
}
