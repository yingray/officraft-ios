import SwiftUI

/// One tappable answer on a reply card.
///
/// The doc's rule: options live on the card itself, so a decision never costs a
/// navigation. Option 0 is the asker's recommendation — the server sends
/// options in preference order — and carries the AI 建議 chip.
///
/// Every row is a single line at 48pt and truncates. That is deliberate: the
/// "Many options" rules promise all the options are visible without scrolling,
/// which only holds if a row's height cannot grow with its wording. The long
/// version of an option lives in the body, one 讀全文 tap away.
struct ReplyOptionRow: View {
    let index: Int
    let text: String
    var isRecommended: Bool
    /// Set once the owner has answered, to show which one they picked.
    var isChosen: Bool = false
    /// Tighter horizontal padding for the inbox card and the task-gate card.
    /// Height and line count stay put — those are fixed by the rules above.
    var isCompact: Bool = false
    var action: (() -> Void)?

    private var highlighted: Bool { isRecommended || isChosen }
    private var radius: CGFloat { isCompact ? OCMetrics.optionRadius : 14 }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 10) {
                numberBadge
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(highlighted ? OC.accent : OC.labelBody)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isChosen {
                    SolidChip(text: "你選的", tint: OC.label, background: OC.bubbleOwn)
                }
                if isRecommended {
                    SolidChip(text: isCompact ? "AI" : "AI 建議", tint: OC.accent)
                }
            }
            .padding(.horizontal, isCompact ? 12 : 14)
            .frame(minHeight: OCMetrics.optionHeight)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(highlighted ? OC.accentFill : OC.label.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(highlighted ? OC.accentBorder : OC.hairline, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel("選項 \(index + 1)：\(text)\(isRecommended ? "，AI 建議" : "")")
    }

    private var numberBadge: some View {
        Text("\(index + 1)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(highlighted ? OC.accent : OC.labelTertiary)
            .frame(width: 22, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        highlighted ? OC.accentBorder : OC.labelQuaternary.opacity(0.5),
                        lineWidth: 1.5
                    )
            )
    }
}
