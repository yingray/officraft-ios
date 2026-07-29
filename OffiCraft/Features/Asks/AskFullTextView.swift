import SwiftUI
import UIKit

// MARK: - The 讀全文 row

/// "There is more behind this" — the explicit way into the long version.
///
/// The doc is firm that deep reading is a tap into full screen and a tap back,
/// never a drawer to drag: no gesture on the card is allowed to be the only way
/// to reach the body.
struct ReadFullTextRow: View {
    /// Blocks in the body — "4 段".
    let blockCount: Int
    let attachmentCount: Int
    var action: () -> Void

    private var meta: String {
        var parts: [String] = []
        if blockCount > 0 { parts.append("\(blockCount) 段") }
        if attachmentCount > 0 { parts.append("\(attachmentCount) 附件") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(.lines, size: 16)
                    .foregroundStyle(OC.labelTertiary)
                Text("讀全文")
                    .font(.ocOption)
                    .foregroundStyle(OC.labelBody)
                Spacer(minLength: 8)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.ocFootnoteSmall)
                        .foregroundStyle(OC.labelTertiary)
                        .lineLimit(1)
                }
                Icon(.chevronRight, size: 14)
                    .foregroundStyle(OC.labelQuaternary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                    .fill(OC.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                            .strokeBorder(OC.hairline, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("讀全文\(meta.isEmpty ? "" : "，\(meta)")")
    }
}

// MARK: - Full screen body

/// 請示全文 — the body on its own screen, with one button back to the options.
///
/// Nothing here answers the card. That is the point: reading and deciding are
/// separated so the reading surface can be as long as it needs to be, and the
/// way back is always the same single button at the bottom.
struct AskFullTextView: View {
    let card: ReplyCard
    /// Shown on the return button so the owner knows what they are going back to.
    let optionCount: Int
    let recommendation: String?

    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var preview: PreviewTarget?

    private var attachments: [Attachment] { card.attachments ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text(MarkdownParser.inline(card.summary))
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(OC.label)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    if let body = card.body, !body.isEmpty {
                        MarkdownView(body, scale: .document)
                    }

                    if !attachments.isEmpty {
                        AttachmentStrip(attachments: attachments) { attachment in
                            preview = previewTarget(for: attachment, in: attachments)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            returnBar
        }
        .background(OC.bg)
        .attachmentPreview($preview,
                           author: store.displayName(for: card.from),
                           timestamp: card.createdAt,
                           taskNo: card.task?.id)
    }

    private var navBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.close, size: 15)
                        .foregroundStyle(OC.label)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(OC.surface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("關閉全文")

                Spacer(minLength: 8)

                VStack(spacing: 1) {
                    Text("請示全文")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OC.label)
                    Text(subtitle)
                        .font(.ocCaptionSmall)
                        .foregroundStyle(OC.labelTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Menu {
                    Button("複製問題") { UIPasteboard.general.string = card.summary }
                    if let body = card.body, !body.isEmpty {
                        Button("複製全文") { UIPasteboard.general.string = body }
                    }
                } label: {
                    Icon(.ellipsis, size: 15)
                        .foregroundStyle(OC.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            Hairline()
        }
    }

    private var subtitle: String {
        let name = store.displayName(for: card.from)
        return "\(name) · \(OCFormat.time(card.createdAt))"
    }

    /// The doc: the bottom of the full-text screen always carries one button
    /// back to the options, and it carries the AI hint with it.
    private var returnBar: some View {
        VStack(spacing: 0) {
            Button { dismiss() } label: {
                HStack(spacing: 10) {
                    Icon(.chevronDown, size: 17)
                        .foregroundStyle(OC.accent)
                    Text("回到 \(optionCount) 個選項")
                        .font(.ocBodyEmphasised)
                        .foregroundStyle(OC.accent)
                    Spacer(minLength: 8)
                    if let recommendation, !recommendation.isEmpty {
                        Text("AI 建議：\(recommendation)")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(OC.accent)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(OC.accentWash))
                            .layoutPriority(-1)
                    }
                }
                .padding(.horizontal, 15)
                .frame(minHeight: 50)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(OC.accentFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(OC.accentBorder, lineWidth: 1)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 10)
        }
        .background(BottomScrim().allowsHitTesting(false))
    }
}

// MARK: - The 其他 N 個 row

/// Where the options past the fifth go, and the way to read a long one in full.
/// Same height as an option so the list still reads as one column, but visibly
/// not a choice — picking it opens the full-screen list rather than answering.
struct MoreOptionsRow: View {
    /// Zero when nothing was folded away and the row exists only because an
    /// option is too long to read where it sits.
    let count: Int
    var action: () -> Void

    private var label: String {
        count > 0 ? "其他 \(count) 個" : "看完整選項"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(.lines, size: 15)
                    .foregroundStyle(OC.labelTertiary)
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OC.labelBody)
                Spacer(minLength: 8)
                Icon(.chevronRight, size: 14)
                    .foregroundStyle(OC.labelQuaternary)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: OCMetrics.optionHeight)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(OC.label.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(OC.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "其他 \(count) 個選項" : "看完整選項")
    }
}

// MARK: - Full screen options

/// 選項全螢幕 — where the folded-away options go once there are more than six.
///
/// It lists every option, not just the folded tail: the owner opened this to
/// compare, and comparing against options left behind on the card would mean
/// holding half the set in their head.
struct AskOptionsFullScreenView: View {
    let card: ReplyCard
    var onAnswer: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var options: [String] { card.options ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            navBar

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if AskOptionLayout.suggestsFewerOptions(total: options.count) {
                        TooManyOptionsNote(count: options.count)
                            .padding(.bottom, 3)
                    }
                    // The one place an option is shown in full: the card and the
                    // detail screen both cap it at two lines so no single
                    // option can bury the rest, and this is where the rest of
                    // the wording lives.
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        ReplyOptionRow(index: index, text: option,
                                       isRecommended: index == 0,
                                       wrapsFully: true) {
                            onAnswer(index)
                            dismiss()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .background(OC.bg)
    }

    private var navBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.close, size: 15)
                        .foregroundStyle(OC.label)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(OC.surface))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("關閉選項")

                Spacer(minLength: 8)

                VStack(spacing: 1) {
                    Text("選一個決定")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OC.label)
                    Text("\(options.count) 個選項")
                        .font(.ocCaptionSmall)
                        .foregroundStyle(OC.labelTertiary)
                }

                Spacer(minLength: 8)

                // Balances the close button so the title stays centred.
                Color.clear.frame(width: 34, height: 34)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            Hairline()
        }
    }
}

// MARK: - Too many options

/// The doc's last rule, verbatim in intent: past ten options the interface is
/// not the thing that is broken, so say so instead of inventing more chrome.
struct TooManyOptionsNote: View {
    let count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(.clock, size: 13)
                .foregroundStyle(OC.waiting)
                .padding(.top, 1)
            Text("\(count) 個選項偏多，回覆前可以請成員先收斂成幾個真的不同的方向。")
                .font(.ocFootnote)
                .foregroundStyle(OC.labelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                .fill(OC.waitingWash)
        )
    }
}
