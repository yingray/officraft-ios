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
    /// Overlong messages the owner has opened out, keyed by message id. Same
    /// reason as the runs above: an id survives an SSE refetch, a position
    /// does not.
    @State private var expandedMessages: Set<String> = []
    /// Whether the reply-card jump has already fired. It happens on the
    /// first load with content and never again.
    @State private var didJumpToHighlight = false

    private var messages: [ChatMessage] { store.messages(with: peerId) }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            transcript
            composer
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        .swipeBackEnabled()
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
                    HStack(spacing: 5) {
                        // A real dot, tinted by presence. It used to be a "●"
                        // baked into the status string, which inherited the
                        // caption's grey and so read "offline" even for a
                        // member who was online.
                        if let presence = peerPresence {
                            PresenceDot(presence: presence, size: 6)
                        }
                        Text(statusLine)
                            .font(.ocCaption)
                            .foregroundStyle(OC.labelTertiary)
                            .lineLimit(1)
                    }
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

    private var peerPresence: Presence? {
        if let member = store.members.first(where: { $0.id == peerId }) { return member.presence }
        if let worker = store.outsourceWorkers.first(where: { $0.id == peerId }) { return worker.presence }
        return nil
    }

    private var statusLine: String {
        var parts: [String] = []
        if let presence = peerPresence {
            parts.append(presence.label)
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

    /// One run with its messages already resolved.
    ///
    /// Deliberately values, not indices into `messages`. The transcript is a
    /// `LazyVStack`, so a row's content closure can run well after it was
    /// declared — and by then an SSE refetch may have replaced the thread with a
    /// shorter array. Indexing at that point is an out-of-range crash; holding
    /// the messages means the worst case is a row that renders one frame stale.
    private struct ResolvedRun: Identifiable {
        let lane: ChatLane
        let messages: [ChatMessage]
        let showsDaySeparator: Bool

        /// Keyed by the first message, never by position: a positional key would
        /// shift the moment a message lands and silently reopen or close a fold.
        var id: String { messages.first?.id ?? "" }
    }

    /// The transcript split into lanes: what the owner and the peer said to each
    /// other, and the agent-to-agent and system stretches folded out of it.
    private var runs: [ResolvedRun] {
        let all = messages
        let calendar = Calendar.current
        let lanes = all.map {
            ChatLane.classify(from: $0.from, to: $0.to, ownerId: session.ownerId)
        }
        // A run must never span two days: the separator is decided per run, and
        // a collapsed run has no inside to put one in. Breaking at midnight
        // keeps every day's header — a plain owner↔peer thread is one long
        // .direct lane, so without this a multi-day history showed only the
        // first day's date and nothing after it.
        let dayBreaks = all.indices.map { index in
            index > 0 && !calendar.isDate(all[index].sentAt,
                                          inSameDayAs: all[index - 1].sentAt)
        }
        return ChatLane.runs(of: lanes, breaks: dayBreaks).map { run in
            ResolvedRun(
                lane: run.lane,
                messages: Array(all[run.range]),
                showsDaySeparator: run.start == 0 || dayBreaks[run.start]
            )
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(runs) { run in
                        if run.showsDaySeparator, let first = run.messages.first {
                            DaySeparator(date: first.sentAt)
                        }
                        if run.lane.isFolded {
                            foldedRun(run, proxy: proxy)
                        } else {
                            ForEach(run.messages) { message in
                                directRow(message, proxy: proxy)
                            }
                        }
                    }
                }
                .padding(.horizontal, OCMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            // The framework's own answer to "a transcript opens on the newest
            // message". This replaces a hand-rolled `scrollTo` that fired once
            // and then again on a 0.35s timer: a one-shot offset always lost
            // the race, because the rows near the bottom are only built when
            // the scroll reaches them, and every markdown body redraws at its
            // measured height after the first layout pass. An anchor is not a
            // one-shot — the scroll view re-applies it whenever the content
            // size changes, which is exactly what this content does.
            //
            // Dropped to nil when a reply card named a message: that entry
            // point owns the position, and a bottom anchor would drag the
            // reader off the target every time a body finished measuring.
            .defaultScrollAnchor(highlightMessageId == nil ? .bottom : nil)
            .scrollDismissesKeyboard(.interactively)
            // Only the highlight jump is left. Keyed on the thread gaining
            // content, because on a first visit the messages are still being
            // fetched when this view appears.
            .onChange(of: messages.count, initial: true) {
                guard let highlightMessageId, !didJumpToHighlight,
                      !messages.isEmpty else { return }
                didJumpToHighlight = true
                // The fold has to be open before the target exists to scroll to.
                expandRun(containing: highlightMessageId)
                proxy.scrollTo(highlightMessageId, anchor: .center)
            }
        }
    }

    /// The fold header's scroll id. Prefixed because the run is keyed by its
    /// first message, and stamping that same string on both the header and the
    /// first bubble would put two views under one id in the scroll namespace.
    private func foldRowId(_ run: ResolvedRun) -> String { "fold-\(run.id)" }

    private func expandRun(containing messageId: String) {
        guard let run = runs.first(where: { run in
            run.lane.isFolded && run.messages.contains { $0.id == messageId }
        }) else { return }
        expandedRuns.insert(run.id)
    }

    @ViewBuilder
    private func foldedRun(_ run: ResolvedRun, proxy: ScrollViewProxy) -> some View {
        let key = run.id
        let isExpanded = expandedRuns.contains(key)

        VStack(alignment: .leading, spacing: 9) {
            ChatFoldRow(lane: run.lane,
                        count: run.messages.count,
                        isExpanded: isExpanded,
                        participants: participants(in: run)) {
                withAnimation(.snappy(duration: 0.22)) {
                    if isExpanded { expandedRuns.remove(key) } else { expandedRuns.insert(key) }
                }
            }
            .id(foldRowId(run))

            if isExpanded {
                ChatFoldedBody(lane: run.lane) {
                    ForEach(run.messages) { message in
                        ChatFoldedMessageRow(
                            lane: run.lane,
                            header: routing(of: message),
                            message: message,
                            isExpanded: expandedMessages.contains(message.id),
                            onToggleExpanded: { toggleMessage(message.id, proxy: proxy) },
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

    private func directRow(_ message: ChatMessage, proxy: ScrollViewProxy) -> some View {
        MessageRow(
            message: message,
            isOwn: message.isOwn(ownerId: session.ownerId),
            isHighlighted: message.id == highlightMessageId,
            isExpanded: expandedMessages.contains(message.id),
            onToggleExpanded: { toggleMessage(message.id, proxy: proxy) },
            onOpenAttachment: { attachment in openPreview(attachment, in: message) },
            onOpenCard: { openCard = CardRoute(id: $0) }
        )
        .id(message.id)
    }

    /// Collapsing takes the message's whole height back out of the transcript,
    /// and the 收合 row sits at the BOTTOM of an open message — so when it is
    /// tapped the message's top edge is far above the screen. A scroll offset
    /// is a distance from the top of the content, so leaving it alone drops the
    /// reader thousands of points further down, into material they have not
    /// read. Re-anchor on the message that was just closed: with it folded to
    /// 320pt the whole thing fits, which is the invariant a transcript has to
    /// hold — the thing you are looking at does not move.
    ///
    /// Expanding needs no such thing: the cap is top-aligned, so a message
    /// grows strictly downward and nothing already on screen shifts.
    private func toggleMessage(_ id: String, proxy: ScrollViewProxy) {
        if expandedMessages.contains(id) {
            expandedMessages.remove(id)
            proxy.scrollTo(id, anchor: .top)
        } else {
            expandedMessages.insert(id)
        }
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
    private func participants(in run: ResolvedRun) -> String {
        guard run.lane == .interAgent else { return "" }
        var seen: [String] = []
        for message in run.messages {
            for id in [message.from, message.to] where !seen.contains(id) {
                seen.append(id)
            }
        }
        if seen.count > 2 { return "\(seen.count) 方" }
        return seen.map { store.displayName(for: $0) }.joined(separator: " ⇄ ")
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 8) {
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
        // No markdown preview here: what the owner writes back is a short
        // reply, not a document. The agents are the ones that send rich
        // markdown, and that still renders in the transcript.
        Composer(
                text: $draft,
                placeholder: "訊息…",
                accentSend: true,
                attachments: $pending,
                onPickPhotos: { isPickingPhotos = true },
                onPickFiles: { isPickingFiles = true }
            ) {
                let body = draft
                let files = pending
                draft = ""
                pending = []
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
    var isExpanded: Bool = false
    var onToggleExpanded: () -> Void = {}
    var onOpenAttachment: (Attachment) -> Void
    var onOpenCard: (String) -> Void

    /// A card announcement gets an outline, so the eye lands on it.
    private var isCardAnnouncement: Bool { message.replyCardId != nil }

    /// The block wears the card's current status: amber while it waits, green
    /// once the owner answered. The status is a read-time join on the wire, so
    /// it is only as fresh as the last thread load.
    ///
    /// There is no status label in this block, so the colour carries the whole
    /// message — hence the unlabelled fallback, which keeps an unusable status
    /// amber instead of grey.
    private var cardTone: ReplyCardTone {
        .forUnlabelledBlock(statusRaw: message.replyCardStatus?.rawValue)
    }

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
                    CollapsibleMessageBody(
                        source: message.body,
                        isExpanded: isExpanded,
                        alignment: .trailing,
                        tint: OC.bubbleOwnText.opacity(0.65),
                        onToggle: onToggleExpanded
                    ) {
                        Text(message.body)
                            .font(.ocCallout)
                            .foregroundStyle(OC.bubbleOwnText)
                            .lineSpacing(4)
                    }
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

                CollapsibleMessageBody(source: message.body,
                                       isExpanded: isExpanded,
                                       onToggle: onToggleExpanded) {
                    MarkdownView(message.body, scale: .message)
                }

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
                                isCardAnnouncement ? cardTone.border
                                    : (isHighlighted ? OC.accentBorder : .clear),
                                lineWidth: 1
                            )
                    )
            )
        }
    }

    private var cardAnnouncementHeader: some View {
        HStack(spacing: 8) {
            SolidChip(text: "請示", tint: cardTone.tint)
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
