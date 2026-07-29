import SwiftUI
import UIKit

/// 請示 · 單卡決策 — one card, one decision, full screen.
///
/// Two layouts, picked by how many options there are. Up to three, the body
/// renders inline and the options sit pinned above the composer — there is room
/// for both. From four up, the doc's "Many options" rules take over: the body
/// collapses to its first paragraph plus a 讀全文 row, and the options move into
/// the content area so every one of them is visible on arrival. Either way the
/// owner never has to scroll before they can decide.
struct AskDetailView: View {
    let cardId: String

    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var card: ReplyCard?
    @State private var ownAnswer = ""
    @State private var preview: PreviewTarget?
    @State private var openTask: TaskRoute?
    @State private var openPeer: PeerRoute?
    @State private var showFullText = false
    @State private var showAllOptions = false

    /// Position within the waiting queue, shown as "1 / 3".
    private var queuePosition: (index: Int, total: Int)? {
        let waiting = store.waitingCards
        guard let index = waiting.firstIndex(where: { $0.id == cardId }) else { return nil }
        return (index + 1, waiting.count)
    }

    /// Options are only offered while the card is still waiting; a handled card
    /// shows what was decided instead, so it always takes the inline layout.
    private var options: [String] {
        guard let card, card.status == .waiting else { return [] }
        return card.options ?? []
    }

    private var usesSummaryLayout: Bool {
        AskOptionLayout.showsReadFullText(total: options.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            if let card {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        askerRow(card)
                        Text(MarkdownParser.inline(card.summary))
                            .font(.ocTitle3)
                            .foregroundStyle(OC.label)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)

                        if usesSummaryLayout {
                            summaryAndOptions(card)
                        } else {
                            if let body = card.body, !body.isEmpty {
                                MarkdownView(body, scale: .document)
                            }

                            if let attachments = card.attachments, !attachments.isEmpty {
                                AttachmentStrip(attachments: attachments) { attachment in
                                    preview = previewTarget(for: attachment, in: attachments)
                                }
                            }
                        }

                        if card.status != .waiting {
                            resolutionBox(card)
                        }
                    }
                    .padding(.horizontal, OCMetrics.headerPadding)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }

                if card.status == .waiting {
                    actionArea(card)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        .navigationDestination(item: $openTask) { route in
            TaskDetailView(taskId: route.id)
        }
        .navigationDestination(item: $openPeer) { route in
            ChatView(peerId: route.id, highlightMessageId: route.highlightMessageId)
        }
        .attachmentPreview($preview,
                           author: card.map { store.displayName(for: $0.from) } ?? "",
                           timestamp: card?.createdAt,
                           taskNo: card?.task?.id)
        .fullScreenCover(isPresented: $showFullText) {
            if let card {
                AskFullTextView(card: card,
                                optionCount: options.count,
                                recommendation: options.first)
            }
        }
        .fullScreenCover(isPresented: $showAllOptions) {
            if let card {
                AskOptionsFullScreenView(card: card) { index in
                    answer(card, optionIdx: index)
                }
            }
        }
        .task {
            card = await store.loadCardDetail(cardId)
        }
    }

    private func answer(_ card: ReplyCard, optionIdx: Int) {
        Task {
            await store.answer(card: card, optionIdx: optionIdx, text: nil)
            dismiss()
        }
    }

    // MARK: Summary layout (4+ options)

    /// Body compressed to its opening paragraph, a way into the full text, then
    /// every option. The whole set has to be reachable without a scroll, which
    /// is why the body gives up its space rather than the options.
    @ViewBuilder
    private func summaryAndOptions(_ card: ReplyCard) -> some View {
        let blocks = MarkdownParser.parse(card.body ?? "")
        let attachments = card.attachments ?? []

        if let context = firstParagraph(blocks) {
            Text(MarkdownParser.inline(context))
                .font(.ocCallout)
                .foregroundStyle(OC.labelSecondary)
                .lineSpacing(4)
                .lineLimit(AskOptionLayout.summaryLineLimit(total: options.count))
                .fixedSize(horizontal: false, vertical: true)
        }

        if !blocks.isEmpty || !attachments.isEmpty {
            ReadFullTextRow(blockCount: blocks.count,
                            attachmentCount: attachments.count) {
                showFullText = true
            }
        }

        Hairline()

        HStack(spacing: 8) {
            Text("選一個決定")
                .font(.system(size: 12.5, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(OC.labelTertiary)
            Spacer()
            Text("\(options.count) 個選項")
                .font(.ocFootnoteSmall)
                .foregroundStyle(OC.labelQuaternary)
        }

        if AskOptionLayout.suggestsFewerOptions(total: options.count) {
            TooManyOptionsNote(count: options.count)
        }

        VStack(spacing: 8) {
            let inline = AskOptionLayout.inlineCount(total: options.count)
            ForEach(Array(options.prefix(inline).enumerated()), id: \.offset) { index, option in
                ReplyOptionRow(index: index, text: option, isRecommended: index == 0) {
                    answer(card, optionIdx: index)
                }
            }

            let overflow = AskOptionLayout.overflowCount(total: options.count)
            if overflow > 0 {
                MoreOptionsRow(count: overflow) { showAllOptions = true }
            }
        }
    }

    private func firstParagraph(_ blocks: [MarkdownBlock]) -> String? {
        for block in blocks {
            if case .paragraph(let text) = block { return text }
        }
        return nil
    }

    // MARK: Chrome

    private var navBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 3) {
                        Icon(.chevronLeft, size: 15)
                        Text("請示").font(.ocBody)
                    }
                    .foregroundStyle(OC.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if let position = queuePosition {
                    Text("\(position.index) / \(position.total)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OC.waiting)
                }

                Spacer()

                Menu {
                    if let card, card.status == .waiting {
                        Button("標為過期", role: .destructive) {
                            Task {
                                await store.expire(card: card)
                                dismiss()
                            }
                        }
                    }
                    if let task = card?.task {
                        Button("查看任務詳情") { openTask = TaskRoute(task) }
                    }
                    Button("複製問題") {
                        UIPasteboard.general.string = card?.summary
                    }
                } label: {
                    Icon(.ellipsis, size: 15)
                        .foregroundStyle(OC.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, OCMetrics.screenPadding)
            Hairline()
        }
    }

    private func askerRow(_ card: ReplyCard) -> some View {
        HStack(spacing: 10) {
            Avatar(name: store.displayName(for: card.from), id: card.from, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                let role = store.roleName(for: card.from)
                Text(role.isEmpty
                     ? store.displayName(for: card.from)
                     : "\(store.displayName(for: card.from)) · \(role)")
                    .font(.ocCalloutEmphasised)
                    .foregroundStyle(OC.label)
                Text(statusLine(card))
                    .font(.ocFootnoteSmall)
                    .foregroundStyle(OC.labelTertiary)
            }
            Spacer(minLength: 6)
            Button {
                openPeer = PeerRoute(id: card.from, highlightMessageId: card.chatMessageId)
            } label: {
                Text("原訊息")
                    .font(.ocCaption)
                    .foregroundStyle(OC.labelSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().strokeBorder(OC.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func statusLine(_ card: ReplyCard) -> String {
        switch card.status {
        case .waiting:
            return "\(OCFormat.stamp(card.createdAt)) · \(OCFormat.waited(since: card.createdAt))"
        case .answered:
            return card.answeredAt.map { OCFormat.answered(at: $0) } ?? OCFormat.stamp(card.createdAt)
        case .expired:
            return card.expiredAt.map { OCFormat.expired(at: $0) } ?? OCFormat.stamp(card.createdAt)
        case .unknown:
            return OCFormat.stamp(card.createdAt)
        }
    }

    // MARK: Decision

    private func actionArea(_ card: ReplyCard) -> some View {
        VStack(spacing: 9) {
            // With four options or more they have already been laid out above,
            // in the content area — pinning them here as well would show every
            // option twice.
            if !usesSummaryLayout {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    ReplyOptionRow(index: index, text: option, isRecommended: index == 0) {
                        answer(card, optionIdx: index)
                    }
                }
            }

            Composer(text: $ownAnswer, placeholder: "自己打一個決定…") {
                Task {
                    await store.answer(card: card, optionIdx: nil, text: ownAnswer)
                    ownAnswer = ""
                    dismiss()
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, OCMetrics.headerPadding)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background(
            BottomScrim().allowsHitTesting(false)
        )
    }

    /// What the owner decided, once the card is no longer waiting.
    @ViewBuilder
    private func resolutionBox(_ card: ReplyCard) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                StatusChip(text: card.status.label, tint: card.status.tint, showsDot: false)
                Spacer()
            }
            if card.status == .answered {
                if let index = card.answer?.optionIdx,
                   let options = card.options,
                   options.indices.contains(index) {
                    ReplyOptionRow(index: index, text: options[index],
                                   isRecommended: index == 0, isChosen: true)
                } else if let text = card.answer?.text, !text.isEmpty {
                    Text(text)
                        .font(.ocCallout)
                        .foregroundStyle(OC.labelBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(OC.accentFill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                                        .strokeBorder(OC.accentBorder, lineWidth: 1)
                                )
                        )
                }
            } else {
                Text("過期不算回答，成員會視情況重開一張新的。")
                    .font(.ocFootnote)
                    .foregroundStyle(OC.labelTertiary)
            }
        }
        .padding(.top, 6)
    }
}
