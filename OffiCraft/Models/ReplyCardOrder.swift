/// Display order for the ask panes: newest first.
///
/// A card minted a minute ago is the one the owner is being asked about right
/// now, so both panes lead with the most recent — 待回覆 on when the card was
/// minted, 近期已處理 on when it was closed.
///
/// The id breaks ties. The list endpoint promises no order of its own, so two
/// cards sharing a timestamp would otherwise land in whatever order the fetch
/// happened to return and swap places between refreshes.
///
/// Generic over the timestamp and id on purpose: the entity types live in a
/// file the logic-test runner does not compile, so the rule is expressed over
/// the two values it needs and tested directly.
enum ReplyCardOrder {
    typealias Key = (ts: Double, id: String)

    /// 待回覆 sorts on when the card was opened — the only timestamp it has.
    static func waitingKey(createdTs: Double, id: String) -> Key {
        (ts: createdTs, id: id)
    }

    /// 近期已處理 mixes two panes: answered cards carry `answeredTs`, expired
    /// ones `expiredTs`. A card is one or the other, so the first non-nil is
    /// the moment it left the inbox; a card with neither sorts oldest rather
    /// than jumping the queue on a missing field.
    static func handledKey(
        answeredTs: Double?,
        expiredTs: Double?,
        id: String
    ) -> Key {
        (ts: answeredTs ?? expiredTs ?? 0, id: id)
    }

    static func newestFirst<T>(_ cards: [T], by key: (T) -> Key) -> [T] {
        cards.sorted { lhs, rhs in
            let left = key(lhs)
            let right = key(rhs)
            if left.ts != right.ts { return left.ts > right.ts }
            return left.id > right.id
        }
    }
}
