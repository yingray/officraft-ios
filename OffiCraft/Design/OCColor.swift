import SwiftUI
import UIKit

/// Semantic colour tokens carried over from the OffiCraft web console
/// (`frontend/src/styles/theme.css`) and the iOS design doc.
///
/// Every token resolves per appearance, so a view never branches on colour scheme.
/// The dark values are the source of truth; the light values are the doc's
/// "請示 · 淺色" screen, tuned so the same information hierarchy survives.
enum OC {

    // MARK: - Surfaces

    /// App canvas. Pure black on dark so the phone bezel disappears.
    static let bg = dyn(light: 0xF2F2F7, dark: 0x000000)
    /// Slightly lifted canvas used by grouped / static pages.
    static let bgElevated = dyn(light: 0xF2F2F7, dark: 0x0B0B0D)
    /// Card and grouped-list background.
    static let surface = dyn(light: 0xFFFFFF, dark: 0x1C1C1E)
    /// Segmented-control selection, chips, inline pills.
    static let surface2 = dyn(light: 0xF7F7FA, dark: 0x2C2C2E)
    /// Code block background — deliberately darker than `surface`.
    static let surfaceCode = dyn(light: 0xF7F7FA, dark: 0x0E0E10)
    /// Tab bar / toolbar chrome.
    static let chrome = dyn(light: 0xF9F9FB, dark: 0x1C1C1E, lightAlpha: 0.95, darkAlpha: 0.92)

    // MARK: - Text

    static let label = dyn(light: 0x000000, dark: 0xFFFFFF)
    static let labelBody = dyn(light: 0x1C1C1E, dark: 0xF2F2F7)
    static let labelSecondary = dyn(light: 0x3C3C43, dark: 0xEBEBF5, lightAlpha: 0.60, darkAlpha: 0.62)
    static let labelTertiary = dyn(light: 0x3C3C43, dark: 0xEBEBF5, lightAlpha: 0.50, darkAlpha: 0.45)
    static let labelQuaternary = dyn(light: 0x3C3C43, dark: 0xEBEBF5, lightAlpha: 0.35, darkAlpha: 0.30)

    // MARK: - Lines

    /// Grouped-list row divider.
    static let separator = dyn(light: 0x3C3C43, dark: 0x545458, lightAlpha: 0.20, darkAlpha: 0.45)
    /// Card outline when the card carries no status colour.
    static let hairline = dyn(light: 0x000000, dark: 0xEBEBF5, lightAlpha: 0.08, darkAlpha: 0.08)

    // MARK: - Semantic status
    //
    // 語意色 (design doc §設計系統摘要):
    //   accent    進行中／已完成／AI 建議
    //   waiting   等我回覆 — the ONLY colour allowed to interrupt you
    //   external  等待外部
    //   taskNo    任務編號        taskType 任務類型
    //   danger    高優先／終止    frozen   凍結／依賴

    static let accent = dyn(light: 0x0B7A5C, dark: 0x6FD6B0)
    /// Filled background behind an accent action (選項卡、主要按鈕).
    static let accentFill = dyn(light: 0xE3F6EE, dark: 0x13312A)
    static let accentBorder = dyn(light: 0x0F8F6B, dark: 0x6FD6B0, lightAlpha: 0.35, darkAlpha: 0.42)
    /// Low-alpha accent wash for "AI 建議" chips.
    static let accentWash = dyn(light: 0x0B7A5C, dark: 0x6FD6B0, lightAlpha: 0.12, darkAlpha: 0.15)

    static let waiting = dyn(light: 0x9A6A08, dark: 0xE0B341)
    static let waitingBorder = dyn(light: 0xBF8F14, dark: 0xE0B341, lightAlpha: 0.30, darkAlpha: 0.42)
    static let waitingWash = dyn(light: 0xBF8F14, dark: 0xE0B341, lightAlpha: 0.10, darkAlpha: 0.10)

    static let external = dyn(light: 0x6B4FD0, dark: 0xA08BD6)
    static let externalText = dyn(light: 0x5A41B8, dark: 0xC8B8EC)
    static let externalWash = dyn(light: 0xA08BD6, dark: 0xA08BD6, lightAlpha: 0.12, darkAlpha: 0.10)

    static let taskNo = dyn(light: 0x3B62C4, dark: 0x8BA3E6)
    static let taskType = dyn(light: 0x0F6F62, dark: 0x7FD0C4)

    static let danger = dyn(light: 0xC0453C, dark: 0xF0736B)
    static let frozen = dyn(light: 0x4B7EA6, dark: 0x8FB6D9)
    static let frozenText = dyn(light: 0x3F6F94, dark: 0xA9C2D8)
    static let frozenMono = dyn(light: 0x3B6A8E, dark: 0xBCD7EE)

    /// Account usage over the safe band (監控 · 過熱).
    static let overheat = dyn(light: 0xC0503F, dark: 0xE8705F)
    /// 已回覆 tick.
    static let success = dyn(light: 0x2E7D3A, dark: 0x6FBF73)
    /// Context / memory usage meter.
    static let memory = dyn(light: 0x3B6FD4, dark: 0x6EA8FE)

    // MARK: - Markdown alert accents

    static let alertNote = dyn(light: 0x3068B8, dark: 0x78AFF0)
    static let alertWarning = dyn(light: 0xB84A4A, dark: 0xF08A8A)
    static let alertImportant = dyn(light: 0x7B45BE, dark: 0xBE96F0)
    static let alertTip = accent
    static let alertCaution = danger

    // MARK: - Avatar palettes
    //
    // Members get a stable palette slot derived from their id, matching the
    // web console's avatar tinting.

    static let avatarBlueBg = dyn(light: 0xE4EAFB, dark: 0x2C3350)
    static let avatarBlueFg = dyn(light: 0x3B62C4, dark: 0x8FABF0)
    static let avatarPurpleBg = dyn(light: 0xEDE8FB, dark: 0x3A2E4D)
    static let avatarPurpleFg = dyn(light: 0x6B4FD0, dark: 0xA99CF0)
    static let avatarTealBg = dyn(light: 0xDDF3EF, dark: 0x1E3B38)
    static let avatarTealFg = dyn(light: 0x0F6F62, dark: 0x7FD0C4)
    static let avatarSandBg = dyn(light: 0xF6EBD5, dark: 0x3B3324)
    static let avatarSandFg = dyn(light: 0x9A6A08, dark: 0xE0B341)
    static let avatarGrayBg = dyn(light: 0xEDEDF0, dark: 0x2C2C2E)
    static let avatarGrayFg = dyn(light: 0x3C3C43, dark: 0xEBEBF5, lightAlpha: 0.55, darkAlpha: 0.50)

    // MARK: - System-ish

    /// Unread / pending badge. Matches the iOS system red per appearance.
    static let badge = dyn(light: 0xFF3B30, dark: 0xFF453A)
    /// Switch "on" tint.
    static let toggleOn = dyn(light: 0x34C759, dark: 0x34C759)
    /// Message bubble sent by the owner.
    static let bubbleOwn = dyn(light: 0xE4EAFB, dark: 0x2C3350)
    static let bubbleOwnText = dyn(light: 0x16244A, dark: 0xFFFFFF)

    // MARK: - Builders

    /// A colour that resolves differently per appearance.
    static func dyn(light: UInt32,
                    dark: UInt32,
                    lightAlpha: CGFloat = 1,
                    darkAlpha: CGFloat = 1) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(uiColor: UIColor(hex: hex, alpha: alpha))
    }
}

// MARK: - Avatar palette assignment

enum AvatarPalette: CaseIterable {
    case blue, purple, teal, sand, gray

    var background: Color {
        switch self {
        case .blue: return OC.avatarBlueBg
        case .purple: return OC.avatarPurpleBg
        case .teal: return OC.avatarTealBg
        case .sand: return OC.avatarSandBg
        case .gray: return OC.avatarGrayBg
        }
    }

    var foreground: Color {
        switch self {
        case .blue: return OC.avatarBlueFg
        case .purple: return OC.avatarPurpleFg
        case .teal: return OC.avatarTealFg
        case .sand: return OC.avatarSandFg
        case .gray: return OC.avatarGrayFg
        }
    }

    /// Stable slot for a member id so an avatar keeps its colour across launches.
    static func forKey(_ key: String) -> AvatarPalette {
        guard !key.isEmpty else { return .gray }
        var hash: UInt32 = 5381
        for byte in key.utf8 {
            hash = (hash &* 33) &+ UInt32(byte)
        }
        let slots: [AvatarPalette] = [.blue, .purple, .teal, .sand]
        return slots[Int(hash % UInt32(slots.count))]
    }
}
