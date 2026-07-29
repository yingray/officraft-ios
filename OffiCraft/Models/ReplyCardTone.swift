/// The colour family a reply card wears, from its status.
///
/// One mapping for every surface that paints a card — the inbox row, the gate
/// step, the 請示 block in a chat. Keyed on the wire status rather than on
/// `ReplyCardStatus` so it stays free of SwiftUI and the logic tests can cover
/// it without an iOS SDK; `ReplyCardStatus.tone` is the typed way in.
enum ReplyCardTone: Hashable {
    /// 等我回覆 — amber, the only colour allowed to interrupt you.
    case waiting
    /// 已回覆 — green.
    case answered
    /// Nothing left to act on: 已過期, or a status this build does not know.
    case inactive

    /// `nil` is a message that carries a card id with no status projected on
    /// it. It stays amber — the colour the block had before the status was
    /// wired in — so an unanswered card never quietly reads as handled.
    init(statusRaw: String?) {
        switch statusRaw {
        case "answered": self = .answered
        case nil, "waiting": self = .waiting
        default: self = .inactive
        }
    }

    /// The tone for a block where the colour is the **only** status signal —
    /// no label beside it to say what the colour means.
    ///
    /// `init(statusRaw:)` sends anything it does not recognise to `.inactive`,
    /// which is right next to a label: grey plus 「—」 reads as "unknown", and
    /// the reader can tell. With no label, grey reads as "nothing left to act
    /// on". So an absent, empty or unrecognised status must fall back to
    /// `.waiting` here.
    ///
    /// The two errors are not equally cheap. The server leaves
    /// `reply_card_status` empty when its read-time card lookup misses, so a
    /// card still waiting on the owner can arrive with no usable status.
    /// Painting that grey can make him miss a decision waiting on him;
    /// painting an already-answered card amber is merely stale. Bias to the
    /// harmless error — do not "tidy" this default back to grey.
    static func forUnlabelledBlock(statusRaw: String?) -> ReplyCardTone {
        switch statusRaw {
        case "answered": return .answered
        case "expired": return .inactive
        default: return .waiting
        }
    }
}
