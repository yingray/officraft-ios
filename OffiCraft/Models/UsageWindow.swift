import Foundation

/// One rate-limit window, as the server shapes it (`server/ocserverd/pacing.go`
/// `PaceWindow`).
///
/// Two things to know. Percentages are on a **0..100** scale on the wire, so
/// they are exposed here as fractions for the UI — the conversion lives in one
/// place. And nil is an honest null (unmeasured), never 0: the server is
/// deliberate about that, so the client must not paper over it.
struct UsageWindow: Codable, Hashable {
    /// How much of the window's allowance is spent, 0..100.
    var usedPct: Double?
    /// How far through the window we are in wall-clock terms, 0..100.
    var elapsedPct: Double?
    /// Server verdict: "hot" when used% runs more than 5 points ahead of
    /// elapsed%, "ok" otherwise, nil when it cannot be judged.
    var pace: String?
    /// Unix epoch when the window resets, when the provider reported one.
    var resetsTs: Double?

    var usedFraction: Double? { usedPct.map { $0 / 100 } }
    var elapsedFraction: Double? { elapsedPct.map { $0 / 100 } }

    /// 過熱 — burning allowance faster than the clock.
    var isHot: Bool { pace == "hot" }

    var resetsAt: Date? { resetsTs.map(Date.init(timeIntervalSince1970:)) }

    private enum CodingKeys: String, CodingKey {
        case usedPct, elapsedPct, pace, resetsAt
    }

    init(usedPct: Double? = nil,
         elapsedPct: Double? = nil,
         pace: String? = nil,
         resetsTs: Double? = nil) {
        self.usedPct = usedPct
        self.elapsedPct = elapsedPct
        self.pace = pace
        self.resetsTs = resetsTs
    }

    /// `resets_at` is typed `any` on the wire and echoed verbatim — an epoch
    /// number in practice, but an ISO-8601 string is explicitly tolerated. A
    /// plain `Double?` would throw on the string form and take the whole
    /// monitoring snapshot down with it, so it is decoded leniently.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPct = try container.decodeIfPresent(Double.self, forKey: .usedPct)
        elapsedPct = try container.decodeIfPresent(Double.self, forKey: .elapsedPct)
        pace = try container.decodeIfPresent(String.self, forKey: .pace)

        if let epoch = try? container.decode(Double.self, forKey: .resetsAt) {
            resetsTs = epoch
        } else if let text = try? container.decode(String.self, forKey: .resetsAt) {
            resetsTs = ISO8601DateFormatter().date(from: text)?.timeIntervalSince1970
        } else {
            resetsTs = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(usedPct, forKey: .usedPct)
        try container.encodeIfPresent(elapsedPct, forKey: .elapsedPct)
        try container.encodeIfPresent(pace, forKey: .pace)
        try container.encodeIfPresent(resetsTs, forKey: .resetsAt)
    }
}
