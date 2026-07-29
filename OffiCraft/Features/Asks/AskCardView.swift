import SwiftUI

/// The inbox card. Everything needed to decide is on it: who asked, how long
/// they have waited, the question, the context line, and the options — tappable
/// in place.
struct AskCardView: View {
    let card: ReplyCard
    var onAnswer: (Int) -> Void
    var onOpenDetail: () -> Void
    var onWriteOwn: () -> Void
    var onOpenTask: ((TaskRef) -> Void)?
    /// Required, not optional: an optional handler meant a caller could ship a
    /// strip of tappable-looking chips that silently did nothing.
    var onOpenAttachment: (Attachment) -> Void
    /// Opens the full-screen option list — the doc's answer to "選項一多怎麼辦".
    var onShowAllOptions: () -> Void

    @Environment(StudioStore.self) private var store

    private var options: [String] { card.options ?? [] }

    var body: some View {
        OCCard(borderTint: card.status == .waiting ? OC.waitingBorder : OC.hairline) {
            headerRow
            questionRow

            if let context = contextLine {
                Text(context)
                    .font(.ocSubhead)
                    .foregroundStyle(OC.labelSecondary)
                    .lineSpacing(3)
                    // A short option list can afford a longer summary; a long
                    // one needs the rows back.
                    .lineLimit(AskOptionLayout.summaryLineLimit(total: options.count))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let attachments = card.attachments, !attachments.isEmpty {
                AttachmentStrip(attachments: attachments, onOpen: onOpenAttachment)
            }

            if card.task != nil {
                taskRow
            }

            if !options.isEmpty {
                if AskOptionLayout.suggestsFewerOptions(total: options.count) {
                    TooManyOptionsNote(count: options.count)
                }

                VStack(spacing: 8) {
                    let inline = AskOptionLayout.inlineCount(total: options.count)
                    ForEach(Array(options.prefix(inline).enumerated()), id: \.offset) { index, option in
                        ReplyOptionRow(
                            index: index,
                            text: option,
                            isRecommended: index == 0,
                            isCompact: true
                        ) {
                            onAnswer(index)
                        }
                    }

                    // Up to six they are all here. Past that the tail folds into
                    // one row that opens the options full screen — the card still
                    // never asks the owner to scroll before deciding. The same
                    // row also appears when nothing was folded but an option is
                    // too long to read in two lines: truncation needs a door.
                    if AskOptionLayout.needsFullList(options) {
                        MoreOptionsRow(count: AskOptionLayout.overflowCount(total: options.count),
                                       action: onShowAllOptions)
                    }
                }
            }

            footerRow
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
    }

    // MARK: Rows

    private var headerRow: some View {
        HStack(spacing: 10) {
            Avatar(name: store.displayName(for: card.from), id: card.from, size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.displayName(for: card.from))
                    .font(.ocCalloutEmphasised)
                    .foregroundStyle(OC.label)
                    .lineLimit(1)
                let role = store.roleName(for: card.from)
                if !role.isEmpty {
                    Text(role)
                        .font(.ocFootnoteSmall)
                        .foregroundStyle(OC.labelTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(OCFormat.stamp(card.createdAt))
                    .font(.ocCaptionSmall)
                    .foregroundStyle(OC.labelQuaternary)
                if card.status == .waiting {
                    // The one line allowed to use the interrupting colour.
                    Text(OCFormat.waited(since: card.createdAt))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(OC.waiting)
                }
            }
        }
    }

    private var questionRow: some View {
        Text(MarkdownParser.inline(card.summary))
            .font(.ocBodyEmphasised)
            .foregroundStyle(OC.label)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// First paragraph of the body, as the "why you are being asked" line.
    private var contextLine: String? {
        guard let body = card.body else { return nil }
        for block in MarkdownParser.parse(body) {
            if case .paragraph(let text) = block { return text }
        }
        return nil
    }

    private var taskRow: some View {
        HStack(spacing: 8) {
            if let typeKey = card.task?.typeKey, !typeKey.isEmpty {
                StatusChip(text: typeKey, tint: OC.taskType, showsDot: false, mono: true)
            }
            if let task = card.task {
                Button {
                    onOpenTask?(task)
                } label: {
                    HStack(spacing: 3) {
                        Text("查看任務詳情").font(.ocFootnote)
                        Icon(.chevronRight, size: 11)
                    }
                    .foregroundStyle(OC.accent)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private var footerRow: some View {
        HStack {
            Button(action: onWriteOwn) {
                HStack(spacing: 5) {
                    Icon(.plus, size: 12)
                    Text("自己打一個回覆").font(.ocFootnote)
                }
                .foregroundStyle(OC.labelTertiary)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onOpenDetail) {
                HStack(spacing: 3) {
                    Text("展開全文").font(.system(size: 13.5, weight: .semibold))
                    Icon(.chevronRight, size: 11)
                }
                .foregroundStyle(OC.accent)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
}

// MARK: - Handled card

/// 近期已處理 — an answered or expired card, collapsed to the decision.
struct HandledAskCardView: View {
    let card: ReplyCard
    var onOpenDetail: () -> Void
    var onOpenAttachment: (Attachment) -> Void

    @Environment(StudioStore.self) private var store

    private var chosenOption: String? {
        guard let index = card.answer?.optionIdx,
              let options = card.options,
              options.indices.contains(index) else { return nil }
        return options[index]
    }

    var body: some View {
        OCCard(borderTint: OC.hairline) {
            HStack(spacing: 10) {
                Avatar(name: store.displayName(for: card.from), id: card.from, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.displayName(for: card.from))
                        .font(.ocCalloutEmphasised)
                        .foregroundStyle(OC.label)
                    let role = store.roleName(for: card.from)
                    if !role.isEmpty {
                        Text(role)
                            .font(.ocFootnoteSmall)
                            .foregroundStyle(OC.labelTertiary)
                    }
                }
                Spacer(minLength: 6)
                Text(statusStamp)
                    .font(.ocCaption)
                    .foregroundStyle(OC.labelQuaternary)
                    .multilineTextAlignment(.trailing)
            }

            Text(MarkdownParser.inline(card.summary))
                .font(.ocCalloutEmphasised)
                .foregroundStyle(OC.label)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Answered and expired cards keep their attachments — the decision
            // is often only readable next to what it was made from.
            if let attachments = card.attachments, !attachments.isEmpty {
                AttachmentStrip(attachments: attachments,
                                compact: true,
                                onOpen: onOpenAttachment)
            }

            if card.status == .answered {
                answeredBox
            } else {
                expiredBox
            }

            Button(action: onOpenDetail) {
                HStack(spacing: 5) {
                    Icon(.chevronRight, size: 11)
                    Text(card.status == .answered ? "查看當初選項" : "查看內容")
                        .font(.ocFootnote)
                }
                .foregroundStyle(OC.labelTertiary)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .opacity(card.status == .expired ? 0.75 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
    }

    private var statusStamp: String {
        if let answeredAt = card.answeredAt { return OCFormat.answered(at: answeredAt) }
        if let expiredAt = card.expiredAt { return OCFormat.expired(at: expiredAt) }
        return OCFormat.stamp(card.createdAt)
    }

    private var answeredBox: some View {
        HStack(alignment: .top, spacing: 8) {
            SolidChip(text: "你選的", tint: OC.label, background: OC.bubbleOwn)
            if card.answer?.optionIdx == 0 {
                SolidChip(text: "AI 建議", tint: OC.accent)
            }
            Text(chosenOption ?? card.answer?.text ?? "已回覆")
                .font(.ocOption)
                .foregroundStyle(OC.labelBody)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                .fill(OC.label.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                        .strokeBorder(OC.hairline, lineWidth: 1)
                )
        )
    }

    private var expiredBox: some View {
        HStack(spacing: 9) {
            StatusChip(text: "已過期", tint: OC.labelTertiary, showsDot: false)
            Text("過期不算回答，成員會重開新卡")
                .font(.ocFootnote)
                .foregroundStyle(OC.labelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                .fill(OC.label.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                        .strokeBorder(OC.hairline, lineWidth: 1)
                )
        )
    }
}
