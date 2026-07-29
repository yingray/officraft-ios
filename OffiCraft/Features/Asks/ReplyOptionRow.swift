import SwiftUI

/// One tappable answer on a reply card.
///
/// The doc's rule: options live on the card itself, so a decision never costs a
/// navigation. Option 0 is the asker's recommendation — the server sends
/// options in preference order — and carries the AI 建議 chip.
///
/// A row is at least 48pt and holds at most two lines, so a long option is
/// mostly readable in place without any one option pushing the rest off screen
/// — the "Many options" rules promise every option is visible on arrival, which
/// only holds if a row's height is bounded.
///
/// Two lines is a compromise, not a fix. Anything longer needs somewhere to be
/// read in full, which is what `wrapsFully` is for: the full-screen option list
/// sets it and lets the text run as long as it needs.
struct ReplyOptionRow: View {
    let index: Int
    let text: String
    var isRecommended: Bool
    /// Set once the owner has answered, to show which one they picked.
    var isChosen: Bool = false
    /// Tighter horizontal padding for the inbox card and the task-gate card.
    var isCompact: Bool = false
    /// Drop the line cap. Only the full-screen list does this — on a card it
    /// would let one option bury the others.
    var wrapsFully: Bool = false
    var action: (() -> Void)?

    private var highlighted: Bool { isRecommended || isChosen }
    private var radius: CGFloat { isCompact ? OCMetrics.optionRadius : 14 }

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(alignment: wrapsFully ? .top : .center, spacing: 10) {
                numberBadge
                Text(text)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(highlighted ? OC.accent : OC.labelBody)
                    .multilineTextAlignment(.leading)
                    .lineLimit(wrapsFully ? nil : 2)
                    .truncationMode(.tail)
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
            // Vertical padding only matters once the text wraps: at one line
            // the 48pt floor already provides it.
            .padding(.vertical, 9)
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
            // Keeps the badge on the first line when the text wraps.
            .padding(.top, wrapsFully ? 1 : 0)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        highlighted ? OC.accentBorder : OC.labelQuaternary.opacity(0.5),
                        lineWidth: 1.5
                    )
            )
    }
}
