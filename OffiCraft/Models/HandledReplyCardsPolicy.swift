/// Fetch and display rules shared by both handled reply-card panes.
///
/// Before a pane has loaded, the count endpoint can still predict exactly how
/// many rows its capped requests can return. After a successful load, the
/// badge uses the rows that actually arrived.
enum HandledReplyCardsPolicy {
    static let answeredFetchLimit = 20
    static let expiredFetchLimit = 10

    static func badgeCount(
        answeredTotal: Int,
        expiredTotal: Int,
        loadedCount: Int? = nil
    ) -> Int {
        if let loadedCount {
            return max(0, loadedCount)
        }
        return min(max(0, answeredTotal), answeredFetchLimit)
            + min(max(0, expiredTotal), expiredFetchLimit)
    }

    /// A delta is invalidation, not data. Advancing this value gives views an
    /// observable signal even when the server-side totals happen not to move.
    static func nextRevision(after revision: UInt64) -> UInt64 {
        revision &+ 1
    }
}
