import SwiftUI
import Observation

/// The app's single read model.
///
/// It follows the SSE contract's reconcile-by-refetch rule (spec/sse.md §2.2):
/// a delta never merges its payload, it just marks a topic dirty and the store
/// refetches that list. Same code path on first load, on pull-to-refresh, and
/// on every reconnect.
@Observable
@MainActor
final class StudioStore {

    // MARK: Collections

    private(set) var waitingCards: [ReplyCard] = []
    private(set) var handledCards: [ReplyCard] = []
    private(set) var cardCounts = ReplyCardCounts()
    /// Advances for every reply-card invalidation, including deltas whose
    /// aggregate counts do not change.
    private(set) var replyCardRevision: UInt64 = 0
    /// The revision represented by `handledCards`; nil until its first load.
    private var handledCardsLoadedRevision: UInt64?
    /// Full bodies fetched on demand for the single-card screen.
    private(set) var cardDetails: [String: ReplyCard] = [:]

    private(set) var tasks: [TaskSummary] = []
    private(set) var taskDetails: [String: TaskDetail] = [:]
    private(set) var openTaskCount = 0

    private(set) var members: [Member] = []
    private(set) var outsourceWorkers: [OutsourceWorker] = []
    private(set) var unreadTotal = 0

    private(set) var monitoring = MonitorSnapshot()
    private(set) var settings = StudioSettings()
    private(set) var threads: [String: [ChatMessage]] = [:]

    private(set) var isLoading = false
    private(set) var lastError: String?

    private unowned let session: AppSession
    private var eventTask: Task<Void, Never>?
    /// Whether `loadAll` has finished once. Gates the stream's first-connect
    /// resync, which would otherwise duplicate that very load.
    private var hasLoadedOnce = false

    init(session: AppSession) {
        self.session = session
    }

    // MARK: - Derived

    /// Roster split — 正職 first, then 外包, matching the office screen.
    var activeMembers: [Member] {
        members.filter(\.isActive).sorted { lhs, rhs in
            if lhs.presence.isAwake != rhs.presence.isAwake { return lhs.presence.isAwake }
            return lhs.name < rhs.name
        }
    }

    var openTasks: [TaskSummary] {
        tasks.filter { !$0.status.isClosed }
    }

    var closedTasks: [TaskSummary] {
        tasks.filter { $0.status.isClosed }
    }

    var tasksWaitingOnOwner: [TaskSummary] {
        tasks.filter { $0.status == .waitingOwner }
    }

    /// The reply-card badge on the tab bar and the iPad sidebar.
    var waitingCardCount: Int { max(cardCounts.waiting, waitingCards.count) }

    /// Number of rows the handled pane shows (or will show when first opened).
    ///
    /// A stale or not-yet-loaded pane uses the count endpoint, capped by the
    /// same limits as its two list requests. A current pane uses the rows that
    /// actually arrived.
    var handledCardCount: Int {
        let loadedCount = handledCardsLoadedRevision == replyCardRevision
            ? handledCards.count
            : nil
        return HandledReplyCardsPolicy.badgeCount(
            answeredTotal: cardCounts.answered,
            expiredTotal: cardCounts.expired,
            loadedCount: loadedCount
        )
    }

    func displayName(for id: String) -> String {
        // Server-authored rows carry a synthetic sender that is not on the
        // roster, so without this they would render their raw id.
        if id == ChatLane.systemSenderId { return "系統" }
        if session.isDemo { return DemoData.displayName(for: id) }
        if let member = members.first(where: { $0.id == id }) { return member.name }
        if let worker = outsourceWorkers.first(where: { $0.id == id }) { return "外包 \(worker.codename)" }
        if id == session.ownerId || id == "owner" { return "我" }
        return id
    }

    func roleName(for id: String) -> String {
        if session.isDemo { return DemoData.roleName(for: id) }
        if let member = members.first(where: { $0.id == id }) { return member.roleName }
        if outsourceWorkers.contains(where: { $0.id == id }) { return "自由代辦" }
        return ""
    }

    /// Which task a member is currently executing — the roster subtitle.
    func currentTaskNo(for memberId: String) -> String? {
        if session.isDemo {
            return DemoData.members.first { $0.id == memberId }?.currentTaskNo
        }
        return openTasks.first { $0.executorId == memberId && $0.status == .inProgress }?.taskNo
    }

    func task(withNo taskNo: String) -> TaskSummary? {
        tasks.first { $0.taskNo.caseInsensitiveCompare(taskNo) == .orderedSame }
    }

    // MARK: - Loading

    func loadAll() async {
        if session.isDemo {
            loadDemo()
            return
        }
        isLoading = true
        defer { isLoading = false }
        // Before the refetches, not after: the connection is already open by
        // now, so a delta landing during this load would otherwise have nobody
        // iterating. This load *is* the resync the reconnect handler asks for,
        // so registering it late costs nothing.
        startListening()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshReplyCards() }
            group.addTask { await self.refreshTasks() }
            group.addTask { await self.refreshOffice() }
            group.addTask { await self.refreshMonitoring() }
            group.addTask { await self.refreshSettings() }
        }
        hasLoadedOnce = true
    }

    private func loadDemo() {
        // Same order as the live panes, so a demo screenshot shows what the
        // owner's own inbox will show.
        waitingCards = ReplyCardOrder.newestFirst(
            DemoData.replyCards.filter { $0.status == .waiting }
        ) { ReplyCardOrder.waitingKey(createdTs: $0.createdTs, id: $0.id) }
        handledCards = ReplyCardOrder.newestFirst(
            DemoData.replyCards.filter { $0.status != .waiting }
        ) {
            ReplyCardOrder.handledKey(
                answeredTs: $0.answeredTs,
                expiredTs: $0.expiredTs,
                id: $0.id
            )
        }
        handledCardsLoadedRevision = replyCardRevision
        cardCounts = DemoData.replyCardCounts
        cardDetails = Dictionary(uniqueKeysWithValues: DemoData.replyCards.map { ($0.id, $0) })
        tasks = DemoData.tasks
        taskDetails = DemoData.taskDetails
        openTaskCount = DemoData.tasks.filter { !$0.status.isClosed }.count
        members = DemoData.members
        outsourceWorkers = DemoData.outsourceWorkers
        unreadTotal = DemoData.members.reduce(0) { $0 + $1.unreadCount }
        monitoring = DemoData.monitoring
        settings = DemoData.settings
        chatRecency = ChatLane.directRecency(
            DemoData.allChat.map { ChatRouting(from: $0.from, to: $0.to, ts: $0.ts) },
            ownerId: DemoData.ownerId
        )
    }

    /// The 待回覆 pane and the counts — everything the inbox needs to paint.
    ///
    /// The handled panes are deliberately not here. Their tab label reads
    /// `cardCounts`, which `/count` already carries, so fetching those two
    /// lists before the owner opens that tab buys nothing — and it is not free:
    /// on the server each one is another full scan of `reply_card` plus a task
    /// lookup per row, and the server runs every query through a single SQLite
    /// connection, so firing them concurrently from here does not make them
    /// cheaper. See `refreshHandledCards()`.
    ///
    /// Each pane is taken on its own `do`. They used to share one `try`, so a
    /// single bad fetch blanked the others.
    func refreshReplyCards() async {
        guard !session.isDemo else { return }

        async let waiting = session.api.replyCards(status: .waiting)
        async let counts = session.api.replyCardCounts()

        do {
            let fresh = ReplyCardOrder.newestFirst(try await waiting) {
                ReplyCardOrder.waitingKey(createdTs: $0.createdTs, id: $0.id)
            }
            // Carry over what is already hydrated. A light row would otherwise
            // overwrite a full card and send it back through hydration on
            // every single refresh. A reply-card delta clears `cardDetails`,
            // so a card that actually changed still comes back fresh.
            waitingCards = fresh.map { cardDetails[$0.id] ?? $0 }
        } catch {
            note(error)
        }
        do {
            cardCounts = try await counts
        } catch {
            note(error)
        }
    }

    /// 近期已處理 — the answered and expired panes, fetched only while that tab
    /// is open.
    func refreshHandledCards() async {
        guard !session.isDemo else { return }

        let requestedRevision = replyCardRevision
        async let answered = session.api.replyCards(
            status: .answered,
            limit: HandledReplyCardsPolicy.answeredFetchLimit
        )
        async let expired = session.api.replyCards(
            status: .expired,
            limit: HandledReplyCardsPolicy.expiredFetchLimit
        )

        do {
            let handled = try await (answered + expired)
            // A newer delta landed while these requests were in flight. Its
            // refresh owns the result; do not make this older snapshot current.
            guard requestedRevision == replyCardRevision else { return }
            handledCards = ReplyCardOrder.newestFirst(handled) {
                ReplyCardOrder.handledKey(
                    answeredTs: $0.answeredTs,
                    expiredTs: $0.expiredTs,
                    id: $0.id
                )
            }
            handledCardsLoadedRevision = requestedRevision
        } catch {
            note(error)
        }
    }

    /// Pull the body and options onto one waiting card.
    ///
    /// `GET /api/reply-cards` returns a deliberately light row — the server's
    /// own note says the list carries no body and no options, they are one
    /// `get_reply_card` away. But the whole design rests on the inbox card
    /// being the decision surface ("選項就在卡上，零跳轉"), so the app has to
    /// fetch them.
    ///
    /// Per card, on demand, driven by the row appearing. It used to be a fixed
    /// dozen fired at launch whether or not anything was on screen — half of
    /// every launch's traffic for cards the owner had not scrolled to yet, on a
    /// server that runs its queries through one connection.
    ///
    /// Best-effort: a card that fails to hydrate still shows its question and
    /// still opens.
    func hydrateCard(_ id: String) async {
        guard !session.isDemo else { return }
        if let cached = cardDetails[id], cached.isDetailed {
            apply(detail: cached)
            return
        }
        // A row can appear, scroll away and come back while its fetch is still
        // in the air; without this that is a second identical request.
        guard !hydrating.contains(id) else { return }
        hydrating.insert(id)
        defer { hydrating.remove(id) }

        guard let detail = try? await session.api.replyCard(id: id) else { return }
        cardDetails[id] = detail
        apply(detail: detail)
    }

    private func apply(detail: ReplyCard) {
        guard let index = waitingCards.firstIndex(where: { $0.id == detail.id }) else { return }
        waitingCards[index] = detail
    }

    /// Cards with a hydration request already in flight.
    private var hydrating: Set<String> = []

    /// Fetches already in the air, so callers that want the same card share one
    /// request instead of racing for it.
    private var detailFetches: [String: Task<ReplyCard?, Never>] = [:]

    /// The list endpoint omits `body`/`options`, so the single-card screen
    /// fetches the full card once and caches it.
    ///
    /// Deduplicated the same way `hydrateCard` is, but by sharing the task
    /// rather than returning early — every caller here wants the card back, so
    /// a late caller awaits the first fetch instead of starting a second one.
    /// The 請示 blocks in a chat are the first caller that asks in bulk: one
    /// transcript can hold several blocks for the same card, and each of them
    /// re-asks on every reply-card revision.
    @discardableResult
    func loadCardDetail(_ id: String) async -> ReplyCard? {
        if let cached = cardDetails[id], cached.isDetailed { return cached }
        guard !session.isDemo else { return cardDetails[id] }
        if let inFlight = detailFetches[id] { return await inFlight.value }

        let fetch = Task { () -> ReplyCard? in
            do {
                let card = try await session.api.replyCard(id: id)
                cardDetails[id] = card
                return card
            } catch {
                note(error)
                return waitingCards.first { $0.id == id }
                    ?? handledCards.first { $0.id == id }
            }
        }
        detailFetches[id] = fetch
        let card = await fetch.value
        detailFetches[id] = nil
        return card
    }

    func refreshTasks() async {
        guard !session.isDemo else { return }
        do {
            tasks = try await session.api.tasks().sorted { lhs, rhs in
                // 等我回覆 floats to the top — it is the only interrupting state.
                if lhs.status.interrupts != rhs.status.interrupts { return lhs.status.interrupts }
                return lhs.updatedTs > rhs.updatedTs
            }
            openTaskCount = try await session.api.openTaskCount().open
        } catch {
            note(error)
        }
    }

    @discardableResult
    func loadTaskDetail(_ id: String) async -> TaskDetail? {
        if session.isDemo { return taskDetails[id] }
        do {
            let detail = try await session.api.task(id: id)
            taskDetails[id] = detail
            return detail
        } catch {
            note(error)
            return taskDetails[id]
        }
    }

    func refreshOffice() async {
        guard !session.isDemo else { return }
        do {
            async let members = session.api.members()
            async let workers = session.api.outsourceWorkers()
            async let unread = session.api.unreadCount()
            // Best-effort: the roster is still correct without it, the list
            // just falls back to its alphabetical order.
            async let recent = try? session.api.recentChat()
            self.members = try await members
            self.outsourceWorkers = try await workers
            self.unreadTotal = try await unread.unread
            if let rows = await recent {
                chatRecency = ChatLane.directRecency(
                    rows.map { ChatRouting(from: $0.from, to: $0.to, ts: $0.ts) },
                    ownerId: session.ownerId
                )
            }
        } catch {
            note(error)
        }
    }

    /// When each peer last exchanged a message with the owner. Absent means
    /// they never have. See `ChatLane.directRecency` for what counts.
    private(set) var chatRecency: [String: Double] = [:]

    func lastMessageTs(for peerId: String) -> Double? { chatRecency[peerId] }

    /// Whoever wrote last is at the top, the way a messages list behaves.
    /// Peers who have never exchanged a message keep the roster's own order —
    /// awake first, then by name — below everyone who has.
    private func byChatRecency<T>(_ items: [T], id: (T) -> String) -> [T] {
        items.enumerated()
            .map { (item: $1, order: $0, ts: chatRecency[id($1)]) }
            .sorted { lhs, rhs in
                switch (lhs.ts, rhs.ts) {
                case let (left?, right?): return left > right
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.order < rhs.order
                }
            }
            .map(\.item)
    }

    var membersByChatRecency: [Member] { byChatRecency(activeMembers) { $0.id } }
    var workersByChatRecency: [OutsourceWorker] { byChatRecency(outsourceWorkers) { $0.id } }

    func refreshMonitoring() async {
        guard !session.isDemo else { return }
        do {
            monitoring = try await session.api.monitoring()
        } catch {
            note(error)
        }
    }

    func refreshSettings() async {
        guard !session.isDemo else { return }
        do {
            settings = try await session.api.settings()
        } catch {
            note(error)
        }
    }

    /// 換手門檻 — the studio's configured value, falling back to the server
    /// default when settings have not loaded yet.
    var handoverFraction: Double {
        settings.handoverFraction ?? 0.75
    }

    // MARK: - Chat

    func messages(with peer: String) -> [ChatMessage] {
        threads[peer] ?? []
    }

    func loadThread(with peer: String) async {
        if session.isDemo {
            threads[peer] = DemoData.chat(with: peer)
            return
        }
        do {
            threads[peer] = try await session.api.chat(with: peer).sorted { $0.ts < $1.ts }
            try? await session.api.markRead(peer: peer)
            await refreshOffice()
        } catch {
            note(error)
        }
    }

    func send(_ body: String,
              to peer: String,
              attachments: [PendingAttachment] = []) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        if session.isDemo {
            let echo = ChatMessage(
                id: UUID().uuidString, from: session.ownerId, to: peer,
                body: trimmed, ts: Date().timeIntervalSince1970,
                attachments: attachments.map {
                    Attachment(id: $0.id.uuidString, filename: $0.filename,
                               mime: $0.mime, isImage: $0.isImage, url: "")
                }
            )
            threads[peer, default: []].append(echo)
            return
        }
        do {
            let sent = try await session.api.sendChat(
                to: peer,
                body: trimmed,
                attachments: uploads(from: attachments)
            )
            threads[peer, default: []].append(sent)
        } catch {
            note(error)
        }
    }

    private func uploads(from attachments: [PendingAttachment]) -> [APIClient.AttachmentUpload]? {
        guard !attachments.isEmpty else { return nil }
        return attachments.map {
            APIClient.AttachmentUpload(filename: $0.filename, mime: $0.mime, data: $0.data)
        }
    }

    // MARK: - Mutations

    /// Answer a waiting card. The inbox removes it optimistically so the tap
    /// feels immediate; a failure puts it straight back.
    func answer(card: ReplyCard,
                optionIdx: Int?,
                text: String?,
                attachments: [PendingAttachment] = []) async {
        // A previously loaded handled pane can already be at its fetch cap.
        // Mark it stale before the optimistic insert so its badge does not
        // briefly claim that an over-cap row would be fetched.
        if !session.isDemo { invalidateReplyCards() }
        let removed = waitingCards
        waitingCards.removeAll { $0.id == card.id }
        cardCounts.waiting = max(0, cardCounts.waiting - 1)
        cardCounts.answered += 1

        var answered = card
        answered.status = .answered
        answered.answeredTs = Date().timeIntervalSince1970
        answered.answer = ReplyCardAnswer(optionIdx: optionIdx, text: text)
        handledCards.insert(answered, at: 0)
        cardDetails[card.id] = answered

        guard !session.isDemo else { return }
        do {
            let updated = try await session.api.answer(
                cardId: card.id,
                optionIdx: optionIdx,
                text: text,
                attachments: uploads(from: attachments)
            )
            cardDetails[card.id] = updated
            await refreshReplyCards()
            await refreshTasks()
        } catch {
            waitingCards = removed
            handledCards.removeAll { $0.id == card.id }
            note(error)
        }
    }

    /// 標為過期 — the left-swipe action, always behind a confirmation.
    func expire(card: ReplyCard) async {
        if !session.isDemo { invalidateReplyCards() }
        let removed = waitingCards
        waitingCards.removeAll { $0.id == card.id }
        var expired = card
        expired.status = .expired
        expired.expiredTs = Date().timeIntervalSince1970
        handledCards.insert(expired, at: 0)

        guard !session.isDemo else { return }
        do {
            try await session.api.expire(cardId: card.id)
            await refreshReplyCards()
        } catch {
            waitingCards = removed
            note(error)
        }
    }

    func setPriority(taskId: String, priority: TaskPriority) async {
        guard !session.isDemo else {
            if let index = tasks.firstIndex(where: { $0.id == taskId }) {
                tasks[index].priority = priority
            }
            taskDetails[taskId]?.priority = priority
            return
        }
        do {
            try await session.api.setPriority(taskId: taskId, priority: priority)
            await refreshTasks()
            _ = await loadTaskDetail(taskId)
        } catch {
            note(error)
        }
    }

    func sendTaskMessage(taskId: String, body: String) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !session.isDemo else { return }
        do {
            try await session.api.sendTaskMessage(taskId: taskId, body: trimmed)
        } catch {
            note(error)
        }
    }

    func wake(member: Member) async {
        guard !session.isDemo else {
            if let index = members.firstIndex(where: { $0.id == member.id }) {
                members[index].presence = .waking
            }
            return
        }
        do {
            try await session.api.activate(memberId: member.id)
            await refreshOffice()
        } catch {
            note(error)
        }
    }

    // MARK: - Attachments

    /// Markdown attachment bodies, cached after the first open.
    private var attachmentText: [String: String] = [:]

    func text(for attachment: Attachment) async -> String? {
        if let cached = attachmentText[attachment.id] { return cached }
        if session.isDemo {
            let body = DemoData.attachmentBodies[attachment.id] ?? "（示範資料沒有這個附件的內容）"
            attachmentText[attachment.id] = body
            return body
        }
        do {
            let data = try await session.api.data(forPath: attachment.url)
            let body = String(data: data, encoding: .utf8) ?? ""
            attachmentText[attachment.id] = body
            return body
        } catch {
            note(error)
            return nil
        }
    }

    func imageData(for attachment: Attachment) async -> Data? {
        guard !session.isDemo else { return nil }
        return try? await session.api.data(forPath: attachment.url)
    }

    /// Quick Look needs bytes on disk, so non-previewable attachments are
    /// staged into the temp directory before being handed over.
    func fileURL(for attachment: Attachment) async -> URL? {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("oc-attachments", isDirectory: true)
            .appendingPathComponent(attachment.filename.isEmpty ? attachment.id : attachment.filename)

        if session.isDemo {
            guard let body = DemoData.attachmentBodies[attachment.id] else { return nil }
            try? FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? body.write(to: destination, atomically: true, encoding: .utf8)
            return destination
        }

        guard let data = try? await session.api.data(forPath: attachment.url) else { return nil }
        try? FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: destination)
        return destination
    }

    // MARK: - SSE

    private func startListening() {
        guard eventTask == nil else { return }
        eventTask = Task { [weak self] in
            guard let self else { return }
            // Every reconnect triggers a full resync — there is no replay.
            await session.events.setReconnectHandler { [weak self] in
                Task { @MainActor in await self?.resyncAll() }
            }
            for await frame in await session.events.frames() {
                await self.apply(frame)
            }
        }
    }

    private func resyncAll() async {
        // The stream fires this on its FIRST connect too, not only on a
        // genuine reconnect — by design, since there is no replay and a caller
        // that connected late would otherwise miss everything. But `loadAll`
        // opens the stream before it starts fetching, so at launch this would
        // run a second, serial copy of the load already in flight. Skip it
        // until the first load has actually happened.
        guard hasLoadedOnce else { return }
        invalidateReplyCards()
        await refreshReplyCards()
        await refreshTasks()
        await refreshOffice()
    }

    /// A delta is a hint, never data. Map the topic to the list it invalidates.
    private func apply(_ frame: EventFrame) async {
        switch frame.topic {
        case .replyCard:
            invalidateReplyCards()
            cardDetails.removeAll()
            await refreshReplyCards()
            await refreshTasks()
            // The 請示 block in a chat carries the card status, and the server
            // publishes no `chat` delta when a card is answered — so an open
            // thread would keep showing the old colour until it reloads.
            // This is for a card answered from somewhere ELSE while the owner
            // sits in the chat: the 助理 answering over MCP, another device, or
            // the expiry sweep. Answering from the 請示 tab does not need it —
            // that pane replaces the chat on both layouts, so the thread is
            // reloaded on the way back anyway.
            if let peer = activeThreadPeer {
                await loadThread(with: peer)
            }
        case .task, .taskManual:
            taskDetails.removeAll()
            await refreshTasks()
        case .member, .outsourceWorker:
            await refreshOffice()
        case .chat, .chatRead:
            await refreshOffice()
            // Refresh the thread the user is looking at, if any.
            if let peer = activeThreadPeer {
                await loadThread(with: peer)
            }
        case .monitoring, .context:
            await refreshMonitoring()
        case .globalContext, .roleDef, .lessons, .unknown:
            break
        }
    }

    private func invalidateReplyCards() {
        replyCardRevision = HandledReplyCardsPolicy.nextRevision(after: replyCardRevision)
    }

    /// Set by the chat screen so incoming deltas refresh the visible thread.
    var activeThreadPeer: String?

    // MARK: - Errors

    private func note(_ error: Error) {
        if let apiError = error as? APIError {
            if apiError == .unauthorized {
                session.handleUnauthorized()
                return
            }
            lastError = apiError.errorDescription
        } else {
            lastError = error.localizedDescription
        }
    }

    func clearError() { lastError = nil }
}
