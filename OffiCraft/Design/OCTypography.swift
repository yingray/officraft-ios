import SwiftUI

/// Type scale from the design doc's "字級 Type scale" card.
///
/// The doc pins exact point sizes, so these are fixed rather than semantic text
/// styles — matching the mock is the requirement. Layout still reflows for
/// larger content because every screen is built from stacks, not fixed frames.
extension Font {

    /// 34 / 700 — page title (請示, 任務, 辦公室, 監控, 更多).
    static let ocLargeTitle = Font.system(size: 34, weight: .bold, design: .default)
    /// 30 / 700 — login headline.
    static let ocDisplay = Font.system(size: 30, weight: .bold)
    /// 26 / 700 — iPad column title.
    static let ocTitle2 = Font.system(size: 26, weight: .bold)
    /// 21–23 / 700 — 請示問題、任務標題、markdown h1.
    static let ocTitle3 = Font.system(size: 22, weight: .bold)
    static let ocTitle3Compact = Font.system(size: 21, weight: .bold)
    /// 17 / 700 — task card title.
    static let ocHeadline = Font.system(size: 17, weight: .bold)
    /// 16–17 — grouped list rows, primary buttons.
    static let ocBody = Font.system(size: 16)
    static let ocBodyLarge = Font.system(size: 17)
    static let ocBodyEmphasised = Font.system(size: 15.5, weight: .semibold)
    /// 15 — message text, option labels.
    static let ocCallout = Font.system(size: 15)
    static let ocCalloutEmphasised = Font.system(size: 15, weight: .semibold)
    static let ocOption = Font.system(size: 14.5, weight: .semibold)
    /// 14 — secondary body.
    static let ocSubhead = Font.system(size: 14)
    /// 12.5–13 — time, role, 完成準則.
    static let ocFootnote = Font.system(size: 13)
    static let ocFootnoteSmall = Font.system(size: 12.5)
    static let ocCaption = Font.system(size: 12)
    static let ocCaptionSmall = Font.system(size: 11.5)
    static let ocMicro = Font.system(size: 11, weight: .bold)

    /// Section header above a grouped list — uppercase, tracked out.
    static let ocSectionHeader = Font.system(size: 12.5, weight: .semibold)

    /// 12–14 — 編號、識別鍵、程式碼.
    static func ocMono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Text {
    /// Uppercase tracked section label ("通知 NOTIFICATIONS", "主機 HOST").
    func ocSectionLabel() -> some View {
        self
            .font(.ocSectionHeader)
            .tracking(0.5)
            .foregroundStyle(OC.labelTertiary)
    }
}

/// Layout constants shared across screens.
enum OCMetrics {
    /// Minimum tap target — the doc calls this out explicitly.
    static let minTapTarget: CGFloat = 44
    /// Screen side padding for scroll content.
    static let screenPadding: CGFloat = 16
    /// Side padding for large titles and page headers.
    static let headerPadding: CGFloat = 20
    /// Card corner radius (請示卡, 任務卡).
    static let cardRadius: CGFloat = 20
    /// Grouped-list container radius.
    static let groupRadius: CGFloat = 16
    /// Inline option / chip radius.
    static let optionRadius: CGFloat = 13
    /// Reply-card option row — fixed by the "Many options" rules so a long
    /// wording cannot push the later options off screen.
    static let optionHeight: CGFloat = 48
    /// Compact card radius (iPad middle column).
    static let compactCardRadius: CGFloat = 14
}
