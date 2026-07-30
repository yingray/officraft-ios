import UIKit
import UserNotifications

/// Push handling.
///
/// The design doc's tiering:
///   立即打斷 — a reply card opened, a task was terminated  → time-sensitive
///   安靜送達 — member messages, task completed             → passive
///   只進摘要 — presence changes, usage drift               → summary only
///
/// and the Lock Screen must be able to answer a card without unlocking, which
/// is what the notification actions below are for.
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// Injected from the app once the session exists.
    weak var session: AppSession?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationCoordinator.shared
        NotificationCoordinator.shared.registerCategories()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        NotificationCoordinator.shared.deviceToken = hex
        guard let session else { return }
        NotificationCoordinator.shared.session = session
        Task { try? await session.api.registerPush(deviceToken: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCoordinator.shared.registrationError = error.localizedDescription
    }
}

/// Owns the notification categories, permission flow, and the routing that
/// happens when the owner taps or answers from the Lock Screen.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    /// Set once APNs hands us a token.
    var deviceToken: String?
    var registrationError: String?

    /// What the owner tapped, consumed by the app on the next foreground pass.
    var pendingRoute: Route?

    enum Route: Equatable {
        case card(String)
        case task(String)
        case chat(peer: String)
    }

    /// Answering from a notification needs the API, so the coordinator holds a
    /// reference once the session is up.
    weak var session: AppSession?

    // MARK: Categories

    enum Category: String {
        /// 請示 — carries up to three answer actions plus "開啟".
        case ask = "OC_ASK"
        /// Task progress / completion.
        case task = "OC_TASK"
        /// A member sent a message.
        case chat = "OC_CHAT"
    }

    /// Action identifiers. `OC_ASK_OPT_<n>` answers option n directly.
    static func optionAction(_ index: Int) -> String { "OC_ASK_OPT_\(index)" }
    static let openAction = "OC_OPEN"

    func registerCategories() {
        // Three answer slots is what fits a Lock Screen card; anything beyond
        // that opens the app.
        let optionActions = (0..<3).map { index in
            UNNotificationAction(
                identifier: Self.optionAction(index),
                title: "選項 \(index + 1)",
                options: [.authenticationRequired]
            )
        }
        let open = UNNotificationAction(
            identifier: Self.openAction,
            title: "開啟",
            options: [.foreground]
        )

        let ask = UNNotificationCategory(
            identifier: Category.ask.rawValue,
            actions: optionActions + [open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let task = UNNotificationCategory(
            identifier: Category.task.rawValue,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        let chat = UNNotificationCategory(
            identifier: Category.chat.rawValue,
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([ask, task, chat])
    }

    // MARK: Permission

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
            return granted
        } catch {
            registrationError = error.localizedDescription
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: Delegate

    /// Cards still interrupt while the app is open — that is the one state
    /// allowed to break your attention.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        let category = notification.request.content.categoryIdentifier
        if category == Category.ask.rawValue {
            return [.banner, .sound, .list]
        }
        return [.list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier

        if let cardId = info["card_id"] as? String {
            if action.hasPrefix("OC_ASK_OPT_"),
               let index = Int(action.replacingOccurrences(of: "OC_ASK_OPT_", with: "")) {
                await answer(cardId: cardId, optionIdx: index)
                return
            }
            pendingRoute = .card(cardId)
            return
        }
        if let taskId = info["task_id"] as? String {
            pendingRoute = .task(taskId)
            return
        }
        if let peer = info["peer_id"] as? String {
            pendingRoute = .chat(peer: peer)
        }
    }

    /// Answering straight from the Lock Screen — no app launch.
    ///
    /// Deliberately NOT behind the in-app confirmation dialog. That dialog
    /// exists because the inbox reorders under the owner's finger; a Lock Screen
    /// action button does not move, and `.authenticationRequired` already puts
    /// Face ID between the tap and the send. Adding a second step here would
    /// cost the one thing this path is for — deciding without opening the app.
    private func answer(cardId: String, optionIdx: Int) async {
        guard let session, session.phase != .signedOut else { return }
        try? await session.api.answer(cardId: cardId, optionIdx: optionIdx, text: nil)
    }
}

// MARK: - Notification tiering

/// Documents the tiering the server should send, and mirrors it for any
/// locally-scheduled notification.
enum NotificationTier {
    /// 立即打斷 — a card is waiting, or a task was terminated.
    case interrupt
    /// 安靜送達 — member messages, task completion.
    case quiet
    /// 只進摘要 — presence and usage changes.
    case summaryOnly

    var interruptionLevel: UNNotificationInterruptionLevel {
        switch self {
        case .interrupt: return .timeSensitive
        case .quiet: return .active
        case .summaryOnly: return .passive
        }
    }

    /// Higher scores sort earlier inside a notification summary.
    var relevanceScore: Double {
        switch self {
        case .interrupt: return 1.0
        case .quiet: return 0.5
        case .summaryOnly: return 0.1
        }
    }
}
