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
    @State private var openCardId: String?

    private var messages: [ChatMessage] { store.messages(with: peerId) }

    var body: some View {
        VStack(spacing: 0) {
            navBar
            transcript
            composer
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        .navigationDestination(item: $openCardId) { id in
            AskDetailView(cardId: id)
        }
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
                    // Attachment picker lives on the composer's + button; this
                    // is the media shortcut from the design doc.
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

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if shouldShowDaySeparator(at: index) {
                            DaySeparator(date: message.sentAt)
                        }
                        MessageRow(
                            message: message,
                            isOwn: message.isOwn(ownerId: session.ownerId),
                            isHighlighted: message.id == highlightMessageId,
                            onOpenAttachment: { attachment in
                                previewAuthor = store.displayName(for: message.from)
                                previewTimestamp = message.sentAt
                                preview = previewTarget(for: attachment,
                                                        in: message.attachments ?? [])
                            },
                            onOpenCard: { openCardId = $0 }
                        )
                        .id(message.id)
                    }
                }
                .padding(.horizontal, OCMetrics.screenPadding)
                .padding(.top, 12)
                .padding(.bottom, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                guard let last = messages.last else { return }
                withAnimation(.smooth) { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .task {
                // Land on the referenced message when arriving from a card.
                if let highlightMessageId {
                    proxy.scrollTo(highlightMessageId, anchor: .center)
                } else if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
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

            Composer(
                text: $draft,
                placeholder: "訊息…",
                accentSend: true,
                showsMarkdownToggle: true,
                markdownPreview: $markdownPreview,
                onAttach: {}
            ) {
                let body = draft
                draft = ""
                markdownPreview = false
                Task { await store.send(body, to: peerId) }
            }
        }
        .padding(.horizontal, OCMetrics.screenPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
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
