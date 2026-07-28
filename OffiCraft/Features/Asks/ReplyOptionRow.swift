import SwiftUI

/// One tappable answer on a reply card.
///
/// The doc's rule: options are at least 44pt and live on the card itself, so a
/// decision never costs a navigation. Option 0 is the asker's recommendation —
/// the server sends options in preference order — and carries the AI 建議 chip.
struct ReplyOptionRow: View {
    let index: Int
    let text: String
    var isRecommended: Bool
    /// Set once the owner has answered, to show which one they picked.
    var isChosen: Bool = false
    var isCompact: Bool = false
    var action: (() -> Void)?

    private var highlighted: Bool { isRecommended || isChosen }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 10) {
                numberBadge
                Text(text)
                    .font(isCompact ? .ocOption : .ocBodyEmphasised)
                    .foregroundStyle(highlighted ? OC.accent : OC.labelBody)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isChosen {
                    SolidChip(text: "你選的", tint: OC.label, background: OC.bubbleOwn)
                }
                if isRecommended {
                    SolidChip(text: isCompact ? "AI" : "AI 建議", tint: OC.accent)
                }
            }
            .padding(.horizontal, isCompact ? 12 : 14)
            .padding(.vertical, isCompact ? 12 : 14)
            .frame(minHeight: OCMetrics.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? OCMetrics.optionRadius : 15, style: .continuous)
                    .fill(highlighted ? OC.accentFill : OC.label.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: isCompact ? OCMetrics.optionRadius : 15, style: .continuous)
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
            .font(.system(size: isCompact ? 11 : 12, weight: .bold))
            .foregroundStyle(highlighted ? OC.accent : OC.labelTertiary)
            .frame(width: isCompact ? 22 : 24, height: isCompact ? 22 : 24)
            .background(
                RoundedRectangle(cornerRadius: isCompact ? 7 : 8, style: .continuous)
                    .strokeBorder(
                        highlighted ? OC.accentBorder : OC.labelQuaternary.opacity(0.5),
                        lineWidth: 1.5
                    )
            )
    }
}
