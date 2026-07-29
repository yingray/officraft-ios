/// Whether a 辦公室 group tab carries an unread dot.
///
/// Read from the whole group, never from the searched or filtered list: a dot
/// that disappeared while the owner typed would say the unread message was
/// gone. Kept free of SwiftUI and of the model types so the logic tests can
/// cover it without an iOS SDK.
enum RosterUnread {
    static func groupHasUnread(_ unreadCounts: [Int]) -> Bool {
        unreadCounts.contains { $0 > 0 }
    }
}
