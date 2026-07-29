import SwiftUI

/// Chat with one member or outsource worker.
///
/// Messages are not "a bubble with a wall of text in it": an agent's message is
/// block-level markdown, so it renders headings, lists, alerts, tables and code
/// the same way the console does.
struct ChatView: View {
    let peerId: String
    var highlightMessageId: String?

    @Environment(StudioStore.self) private var store
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var markdownPreview = false
    @State private var preview: PreviewTarget?
    @State private var previewAuthor = ""
    @State private var previewTimestamp: Date?
    @State private var openCard: CardRoute?
    @State private var pending: [PendingAttachment] = []
    @State private var isPickingPhotos = false
    @State private var isPickingFiles = false
    @State private var attachmentError: String?
    /// Folded runs the owner has opened, keyed by their first message id.
    /// Empty by design: inter-agent chatter and handover notices start closed.
    @State private var expandedRuns: Set<String> = []

    private var messages: [ChatMessage] { store.messages(with: peerId) }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            transcript
            composer
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        .navigationDestination(item: $openCard) { route in
            AskDetailView(cardId: route.id)
        }
        // Only the preview presenter lives on the screen root. The picker and
        // its alert hang off the composer, which owns them anyway — several
        // sheet-class modifiers on one node fight each other.
        .attachmentPreview($preview, author: previewAuthor, timestamp: previewTimestamp)
        .task {
            store.activeThreadPeer = peerId
            await store.loadThread(with: peerId)
        }
        .onDisappear { store.activeThreadPeer = nil }
    }

    // MARK: Chrome

    private var navBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Button { dismiss() } label: {
                    Icon(.chevronLeft, size: 16)
                        .foregroundStyle(OC.accent)
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Avatar(name: store.displayName(for: peerId), id: peerId, size: 32)

                VStack(alignment: .leading, spacing: 0) {
                    Text(store.displayName(for: peerId))
                        .font(.ocCalloutEmphasised)
                        .foregroundStyle(OC.label)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(.ocCaption)
                        .foregroundStyle(OC.labelTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isPickingPhotos = true
                } label: {
                    Icon(.image, size: 19)
                        .foregroundStyle(OC.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, OCMetrics.screenPadding)
            Hairline()
        }
    }

    private var statusLine: String {
        var parts: [String] = []
        if let member = store.members.first(where: { $0.id == peerId }) {
            parts.append("● \(member.presence.label)")
        } else if let worker = store.outsourceWorkers.first(where: { $0.id == peerId }) {
            parts.append("● \(worker.presence.label)")
        }
        if let taskNo = store.currentTaskNo(for: peerId) {
            parts.append("進行中 #\(taskNo)")
        } else if let worker = store.outsourceWorkers.first(where: { $0.id == peerId }),
                  let taskId = worker.taskId,
                  let task = store.tasks.first(where: { $0.id == taskId }) {
            parts.append("\(task.typeKey) · \(task.title)")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Transcript

    /// The transcript split into lanes: what the owner and the peer said to each
    /// other, and the agent-to-agent and system stretches folded out of it.
    private var runs: [ChatLaneRun] {
        ChatLane.runs(of: messages.map {
            ChatLane.classify(from: $0.from, to: $0.to, ownerId: session.ownerId)
        })
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(runs, id: \.start) { run in
                        if shouldShowDaySeparator(at: run.start) {
                            DaySeparator(date: messages[run.start].sentAt)
                        }
                        if run.lane.isFolded {
                            foldedRun(run)
                        } else {
                            ForEach(run.range, id: \.self) { index in
                                directRow(messages[index])
                            }
                        }
                    }
                }
                .padding(.horizontal, OCMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                guard let anchor = bottomAnchorId else { return }
                withAnimation(.smooth) { proxy.scrollTo(anchor, anchor: .bottom) }
            }
            .task {
                // Arriving from a reply card must land on the message that
                // announced it — including when it sits inside a folded run,
                // which would otherwise not be in the hierarchy to scroll to.
                if let highlightMessageId {
                    expandRun(containing: highlightMessageId)
                    proxy.scrollTo(highlightMessageId, anchor: .center)
                } else if let anchor = bottomAnchorId {
                    proxy.scrollTo(anchor, anchor: .bottom)
                }
            }
        }
    }

    /// The id to scroll to for "the bottom". A collapsed run hides its messages,
    /// so the last message's id may not exist in the hierarchy — the run's own
    /// id is the row that does.
    private var bottomAnchorId: String? {
        guard let last = runs.last else { return nil }
        if last.lane.isFolded, !expandedRuns.contains(runId(last)) {
            return runId(last)
        }
        return messages[last.range.upperBound - 1].id
    }

    /// Runs are keyed by their first message, not by their index: an index would
    /// move the moment a new message lands and quietly reopen or close a fold.
    private func runId(_ run: ChatLaneRun) -> String { messages[run.start].id }

    private func expandRun(containing messageId: String) {
        guard let index = messages.firstIndex(where: { $0.id == messageId }),
              let run = runs.first(where: { $0.range.contains(index) }),
              run.lane.isFolded else { return }
        expandedRuns.insert(runId(run))
    }

    @ViewBuilder
    private func foldedRun(_ run: ChatLaneRun) -> some View {
        let key = runId(run)
        let isExpanded = expandedRuns.contains(key)

        VStack(alignment: .leading, spacing: 9) {
            ChatFoldRow(lane: run.lane,
                        count: run.count,
                        isExpanded: isExpanded,
                        participants: participants(in: run)) {
                withAnimation(.snappy(duration: 0.22)) {
                    if isExpanded { expandedRuns.remove(key) } else { expandedRuns.insert(key) }
                }
            }
            .id(key)

            if isExpanded {
                ChatFoldedBody(lane: run.lane) {
                    ForEach(run.range, id: \.self) { index in
                        let message = messages[index]
                        ChatFoldedMessageRow(
                            lane: run.lane,
                            header: routing(of: message),
                            message: message,
                            onOpenAttachment: { attachment in
                                openPreview(attachment, in: message)
                            }
                        )
                        .id(message.id)
                    }
                }
            }
        }
    }

    private func directRow(_ message: ChatMessage) -> some View {
        MessageRow(
            message: message,
            isOwn: message.isOwn(ownerId: session.ownerId),
            isHighlighted: message.id == highlightMessageId,
            onOpenAttachment: { attachment in openPreview(attachment, in: message) },
            onOpenCard: { openCard = CardRoute(id: $0) }
        )
        .id(message.id)
    }

    private func openPreview(_ attachment: Attachment, in message: ChatMessage) {
        previewAuthor = store.displayName(for: message.from)
        previewTimestamp = message.sentAt
        preview = previewTarget(for: attachment, in: message.attachments ?? [])
    }

    /// "Kyle → Sasha" — the doc's rule for an opened fold. Without it a folded
    /// row has nothing on screen naming who spoke: the owner is on neither end,
    /// so bubble alignment cannot carry it.
    private func routing(of message: ChatMessage) -> String {
        "\(store.displayName(for: message.from)) → \(store.displayName(for: message.to))"
    }

    /// "Kyle ⇄ Sasha" — who a collapsed inter-agent run is between. Ordered by
    /// first appearance so the row does not reshuffle as messages arrive.
    private func participants(in run: ChatLaneRun) -> String {
        guard run.lane == .interAgent else { return "" }
        var seen: [String] = []
        for index in run.range {
            for id in [messages[index].from, messages[index].to] where !seen.contains(id) {
                seen.append(id)
            }
        }
        if seen.count > 2 { return "\(seen.count) 方" }
        return seen.map { store.displayName(for: $0) }.joined(separator: " ⇄ ")
    }

    private func shouldShowDaySeparator(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(messages[index].sentAt,
                                        inSameDayAs: messages[index - 1].sentAt)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 8) {
            if markdownPreview, !draft.isEmpty {
                ScrollView {
                    MarkdownView(draft, scale: .message)
                        .padding(12)
                }
                .frame(maxHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(OC.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(OC.accentBorder, lineWidth: 1)
                        )
                )
            }

            composerBar
        }
        .padding(.horizontal, OCMetrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .attachmentPicker(attachments: $pending,
                          isPresentingPhotos: $isPickingPhotos,
                          isPresentingFiles: $isPickingFiles,
                          errorMessage: $attachmentError)
        .alert("附件加不進來",
               isPresented: Binding(get: { attachmentError != nil },
                                    set: { if !$0 { attachmentError = nil } })) {
            Button("好") { attachmentError = nil }
        } message: {
            Text(attachmentError ?? "")
        }
    }

    private var composerBar: some View {
        Composer(
                text: $draft,
                placeholder: "訊息…",
                accentSend: true,
                showsMarkdownToggle: true,
                markdownPreview: $markdownPreview,
                attachments: $pending,
                onPickPhotos: { isPickingPhotos = true },
                onPickFiles: { isPickingFiles = true }
            ) {
                let body = draft
                let files = pending
                draft = ""
                pending = []
                markdownPreview = false
                Task { await store.send(body, to: peerId, attachments: files) }
            }
    }
}

// MARK: - Day separator

private struct DaySeparator: View {
    let date: Date

    var body: some View {
        Text(OCFormat.daySeparator(date))
            .font(.ocCaptionSmall)
            .foregroundStyle(OC.labelTertiary)
            .padding(.horizontal, 11)
            .padding(.vertical, 3)
            .background(Capsule().fill(OC.surface))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }
}

// MARK: - Message

private struct MessageRow: View {
    let message: ChatMessage
    let isOwn: Bool
    var isHighlighted: Bool = false
    var onOpenAttachment: (Attachment) -> Void
    var onOpenCard: (String) -> Void

    /// A card announcement gets the amber outline, so the eye lands on it.
    private var isCardAnnouncement: Bool { message.replyCardId != nil }

    var body: some View {
        HStack {
            if isOwn { Spacer(minLength: 44) }
            content
            if !isOwn { Spacer(minLength: 26) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isOwn {
            VStack(alignment: .trailing, spacing: 8) {
                if !message.body.isEmpty {
                    Text(message.body)
                        .font(.ocCallout)
                        .foregroundStyle(OC.bubbleOwnText)
                        .lineSpacing(4)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 20, bottomLeadingRadius: 20,
                                bottomTrailingRadius: 6, topTrailingRadius: 20,
                                style: .continuous
                            )
                            .fill(OC.bubbleOwn)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
                // What the owner sent is previewable too — it used to render
                // as text only, so their own files were invisible.
                if let attachments = message.attachments, !attachments.isEmpty {
                    AttachmentStrip(attachments: attachments, onOpen: onOpenAttachment)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                if isCardAnnouncement {
                    cardAnnouncementHeader
                }

                MarkdownView(message.body, scale: .message)

                if let attachments = message.attachments, !attachments.isEmpty {
                    AttachmentStrip(attachments: attachments, onOpen: onOpenAttachment)
                }

                Text(OCFormat.time(message.sentAt))
                    .font(.ocCaptionSmall)
                    .foregroundStyle(OC.labelQuaternary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(OC.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(
                                isCardAnnouncement ? OC.waitingBorder
                                    : (isHighlighted ? OC.accentBorder : .clear),
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    private var cardAnnouncementHeader: some View {
        HStack(spacing: 8) {
            SolidChip(text: "請示", tint: OC.waiting)
            Spacer()
            Button {
                if let cardId = message.replyCardId { onOpenCard(cardId) }
            } label: {
                HStack(spacing: 3) {
                    Text("在請示頁處理").font(.ocCaption)
                    Icon(.chevronRight, size: 10)
                }
                .foregroundStyle(OC.labelTertiary)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
