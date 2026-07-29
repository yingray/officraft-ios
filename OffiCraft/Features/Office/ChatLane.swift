import Foundation

/// Which conversation a chat row actually belongs to.
///
/// `GET /api/chat?with=<peer>` returns every message the peer touched, so the
/// owner's thread carries three different conversations at once: what they said
/// to each other, what the peer said to *other* agents, and what the server
/// wrote when a task changed hands. The doc's rule is that only the first one
/// is the thread — the other two fold into a single row until the owner asks.
///
/// Kept free of SwiftUI and of the model types so the logic tests can cover the
/// classification without an iOS SDK.
enum ChatLane: String, Hashable {
    /// Owner ↔ this peer. The conversation the screen is actually for.
    case direct
    /// Agent ↔ agent, with the owner on neither end.
    case interAgent
    /// Server-authored task notices — reassign handovers and dependency
    /// releases. The wire calls the sender "system".
    case system

    /// The synthetic sender the server stamps on its own messages
    /// (`wireSystemSender`), so an automated handover is never misattributed to
    /// the owner. It is deliberately not a roster id.
    static let systemSenderId = "system"

    /// The id the server uses for the owner when the app has not been told a
    /// different one.
    static let defaultOwnerId = "owner"

    static func classify(from: String, to: String, ownerId: String) -> ChatLane {
        // System first: its rows have the owner on neither end, so the
        // inter-agent test below would otherwise swallow them.
        if from == systemSenderId { return .system }
        if isOwner(from, ownerId) || isOwner(to, ownerId) { return .direct }
        return .interAgent
    }

    private static func isOwner(_ id: String, _ ownerId: String) -> Bool {
        id == ownerId || id == defaultOwnerId
    }

    var isFolded: Bool { self != .direct }
}

/// A stretch of consecutive rows in the same lane.
///
/// Runs are what the transcript renders: a `.direct` run is a plain stretch of
/// bubbles, a folded run is one tappable row that hides its messages until the
/// owner opens it.
struct ChatLaneRun: Equatable {
    let lane: ChatLane
    /// Index of the first message in the flat, time-ordered list.
    let start: Int
    let count: Int

    var range: Range<Int> { start ..< (start + count) }
}

extension ChatLane {
    /// Collapse a time-ordered lane sequence into consecutive runs.
    ///
    /// Only neighbours merge. Two inter-agent exchanges with the owner's own
    /// reply between them stay two separate folds — merging across would move
    /// messages past each other in time, which is a worse lie than an extra row.
    ///
    /// `breaks[i] == true` forces a run to start at `i` even when the lane is
    /// unchanged. The transcript uses it for midnight: a run is the unit the day
    /// separator is decided on, so a run that spanned two days would swallow the
    /// second day's header — and a collapsed run cannot show a divider inside
    /// itself at all.
    static func runs(of lanes: [ChatLane], breaks: [Bool] = []) -> [ChatLaneRun] {
        var runs: [ChatLaneRun] = []
        var index = 0
        while index < lanes.count {
            let lane = lanes[index]
            var length = 1
            while index + length < lanes.count,
                  lanes[index + length] == lane,
                  !(breaks.indices.contains(index + length) && breaks[index + length]) {
                length += 1
            }
            runs.append(ChatLaneRun(lane: lane, start: index, count: length))
            index += length
        }
        return runs
    }
}
