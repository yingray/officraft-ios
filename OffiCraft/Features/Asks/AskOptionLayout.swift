import Foundation

/// The design doc's "選項一多怎麼辦 / Many options" rules, in one place.
///
/// The point of the section is that a decision never costs a gesture: every
/// option is on screen when the card opens, and reading the long version is an
/// explicit tap into full screen and one tap back — not a drawer to drag.
///
///     1–3   summary may run to 4–5 lines, every option inline, no 讀全文 row
///     4–6   summary squeezed to 2–3 lines plus a 讀全文 row, options still all inline
///     7+    first 5 inline, the rest collapse into 其他 N 個 (a full-screen list)
///     10+   also tell the owner to ask the member to narrow it down
///
/// Kept free of SwiftUI so the logic tests can cover it without an iOS SDK.
enum AskOptionLayout {

    /// Above this many options the card stops listing them all.
    static let inlineCap = 5
    /// The largest set that still fits on the card in full.
    static let allInlineLimit = 6
    /// Past this the problem is the question, not the layout.
    static let tooManyThreshold = 10

    /// How many options render as tappable rows on the card.
    static func inlineCount(total: Int) -> Int {
        guard total > allInlineLimit else { return max(0, total) }
        return inlineCap
    }

    /// How many are folded into the 其他 N 個 row. Zero when they all fit.
    static func overflowCount(total: Int) -> Int {
        max(0, total - inlineCount(total: total))
    }

    /// Lines the context summary gets before it truncates. A short option list
    /// leaves room to read; a long one has to give that room back.
    static func summaryLineLimit(total: Int) -> Int {
        total <= 3 ? 5 : 3
    }

    /// Whether the card shows the 讀全文 row. With three options or fewer the
    /// body fits on the card itself, so the row would be a detour to nowhere.
    static func showsReadFullText(total: Int) -> Bool {
        total > 3
    }

    /// Whether to tell the owner the member should converge the options.
    static func suggestsFewerOptions(total: Int) -> Bool {
        total >= tooManyThreshold
    }
}
