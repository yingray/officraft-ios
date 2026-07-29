import SwiftUI

/// 請示 — the inbox. The heart of the app: a decision per card, answered in
/// place, no navigation required.
struct AsksView: View {
    @Environment(StudioStore.self) private var store
    @Environment(AppSession.self) private var session

    @State private var tab: Tab = .waiting
    @State private var openCard: ReplyCard?
    @State private var writeOwnFor: ReplyCard?
    @State private var expireCandidate: ReplyCard?
    @State private var openTask: TaskRoute?
    @State private var preview: PreviewTarget?
    @State private var previewAuthorId: String?
    @State private var allOptionsFor: ReplyCard?

    private enum Tab: Hashable { case waiting, handled }

    var body: some View {
        VStack(spacing: 0) {
            // No header buttons: the tabs right below already switch panes,
            // with names and counts on them.
            PageHeader(title: "請示", eyebrow: studioName)

            SegmentedTabs(
                items: [
                    .init(value: Tab.waiting, title: "待回覆 \(store.waitingCardCount)"),
                    .init(value: Tab.handled, title: "近期已處理 \(store.cardCounts.answered)"),
                ],
                selection: $tab
            )
            .padding(.horizontal, OCMetrics.headerPadding)
            .padding(.bottom, 12)

            if tab == .handled {
                Text("近 24 小時 · 新到舊")
                    .font(.ocFootnoteSmall)
                    .foregroundStyle(OC.labelQuaternary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OCMetrics.headerPadding)
                    .padding(.bottom, 8)
            }

            list
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        .navigationDestination(item: $openCard) { card in
            AskDetailView(cardId: card.id)
        }
        .navigationDestination(item: $openTask) { route in
            TaskDetailView(taskId: route.id)
        }
        .attachmentPreview($preview, author: previewAuthor, timestamp: nil)
        // These live on the root, not on `list`: `list` switches between an
        // empty-state ScrollView and a List, and a modifier attached inside
        // that branch is torn down the moment an SSE refresh empties the
        // inbox — taking an open sheet with it.
        .sheet(item: $writeOwnFor) { card in
            WriteOwnAnswerSheet(card: card)
        }
        .fullScreenCover(item: $allOptionsFor) { card in
            AskOptionsFullScreenView(card: card) { index in
                Task { await store.answer(card: card, optionIdx: index, text: nil) }
            }
        }
        .confirmationDialog(
            "把這張請示標為過期？",
            isPresented: Binding(
                get: { expireCandidate != nil },
                set: { if !$0 { expireCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("標為過期", role: .destructive) {
                if let card = expireCandidate {
                    Task { await store.expire(card: card) }
                }
                expireCandidate = nil
            }
            Button("取消", role: .cancel) { expireCandidate = nil }
        } message: {
            Text("過期不算回答，成員會視情況重開一張新的。")
        }
        // The handled panes are two more full table scans on the server, so
        // they are pulled when the owner opens that tab and not before. The
        // tab's own label comes from the counts endpoint, which the inbox
        // fetches anyway.
        .task(id: tab) {
            if tab == .handled { await store.refreshHandledCards() }
        }
        // A card answered elsewhere moves the count; while this pane is open,
        // that is the signal to re-read it.
        .onChange(of: store.cardCounts.answered) {
            if tab == .handled { Task { await store.refreshHandledCards() } }
        }
        .refreshable { await refresh() }
    }

    private func refresh() async {
        await store.refreshReplyCards()
        if tab == .handled { await store.refreshHandledCards() }
    }

    private var studioName: String {
        session.isDemo ? DemoData.studioName.uppercased() : "OFFICRAFT"
    }

    /// Whoever authored the attachment currently being previewed.
    private var previewAuthor: String {
        guard let from = previewAuthorId else { return "" }
        return store.displayName(for: from)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        let cards = tab == .waiting ? store.waitingCards : store.handledCards

        if cards.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: .inbox,
                    title: tab == .waiting ? "目前沒有等你的請示" : "近期沒有已處理的請示",
                    message: tab == .waiting
                        ? "成員需要你拍板時，卡片會出現在這裡。"
                        : nil
                )
            }
            .refreshable { await store.refreshReplyCards() }
        } else {
            List {
                ForEach(cards) { card in
                    row(for: card)
                        .listRowInsets(EdgeInsets(top: 6, leading: OCMetrics.screenPadding,
                                                  bottom: 6, trailing: OCMetrics.screenPadding))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    @ViewBuilder
    private func row(for card: ReplyCard) -> some View {
        if card.status == .waiting {
            AskCardView(
                card: card,
                onAnswer: { index in
                    Task { await store.answer(card: card, optionIdx: index, text: nil) }
                },
                onOpenDetail: { openCard = card },
                onWriteOwn: { writeOwnFor = card },
                onOpenTask: { openTask = TaskRoute($0) },
                onOpenAttachment: { attachment in
                    previewAuthorId = card.from
                    preview = previewTarget(for: attachment, in: card.attachments ?? [])
                },
                onShowAllOptions: { allOptionsFor = card }
            )
            // The options are what makes this card decidable, and the list row
            // does not carry them. Fetched when the row appears rather than a
            // dozen at launch, so the inbox costs one request per card the
            // owner can actually see.
            .task { await store.hydrateCard(card.id) }
            // Interaction rules: left swipe marks expired (confirmed), right
            // swipe jumps to the original message.
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    openCard = card
                } label: {
                    Label("原訊息", systemImage: "arrow.uturn.backward")
                }
                .tint(OC.taskNo)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    expireCandidate = card
                } label: {
                    Label("標為過期", systemImage: "clock.badge.xmark")
                }
                .tint(OC.waiting)
            }
        } else {
            HandledAskCardView(
                card: card,
                onOpenDetail: { openCard = card },
                onOpenAttachment: { attachment in
                    previewAuthorId = card.from
                    preview = previewTarget(for: attachment, in: card.attachments ?? [])
                }
            )
        }
    }
}

// MARK: - Write your own answer

/// 自己打一個決定 — a free-text answer instead of one of the offered options.
struct WriteOwnAnswerSheet: View {
    let card: ReplyCard
    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(MarkdownParser.inline(card.summary))
                    .font(.ocBodyEmphasised)
                    .foregroundStyle(OC.label)
                    .fixedSize(horizontal: false, vertical: true)

                TextEditor(text: $text)
                    .font(.ocCallout)
                    .foregroundStyle(OC.labelBody)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 140)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(OC.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(OC.hairline, lineWidth: 1)
                            )
                    )
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("自己打一個決定…")
                                .font(.ocCallout)
                                .foregroundStyle(OC.labelQuaternary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                Text("你寫的內容會原文送回給成員，取代選項。")
                    .font(.ocFootnoteSmall)
                    .foregroundStyle(OC.labelTertiary)

                Spacer()
            }
            .padding(20)
            .background(OC.bg)
            .navigationTitle("自己回覆")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送出") {
                        Task { await store.answer(card: card, optionIdx: nil, text: text) }
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
    }
}
