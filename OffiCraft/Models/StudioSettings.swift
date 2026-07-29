import Foundation

/// `GET/PATCH /api/settings` — the owner-adjustable surface
/// (`server/ocserverd/wire.go` settingsDTO). Field names are the server's, not
/// a guess: every one of these is checked against that DTO.
struct StudioSettings: Codable, Hashable {
    /// Session lifetime in SECONDS.
    var tokenTtl: Int?
    /// 換手門檻 — context percentage (0..100) that triggers an automatic
    /// handover.
    var handoverPct: Int?
    var codexCompactionThreshold: Int?
    var outsourceMaxParallel: Int?
    /// "" means never set; the studio name falls back to a default.
    var orgName: String?
    var ownerName: String?
    var pushContactEmail: String?
    var displayTheme: String?
    var displayLanguage: String?
    var displayWide: Bool?
    var updaterReceiveBeta: Bool?
    var updaterAutoUpdate: Bool?

    /// The handover threshold as a fraction, for the meters.
    var handoverFraction: Double? { handoverPct.map { Double($0) / 100 } }

    /// 登入有效期, rounded to whole days for display.
    var sessionDays: Int? { tokenTtl.map { max(1, $0 / 86_400) } }

    /// Present the studio name only when the owner actually set one.
    var studioName: String? {
        guard let orgName, !orgName.isEmpty else { return nil }
        return orgName
    }

    var ownerDisplayName: String? {
        guard let ownerName, !ownerName.isEmpty else { return nil }
        return ownerName
    }
}
