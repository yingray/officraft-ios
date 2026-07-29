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
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshReplyCards() }
            group.addTask { await self.refreshTasks() }
            group.addTask { await self.refreshOffice() }
            group.addTask { await self.refreshMonitoring() }
            group.addTask { await self.refreshSettings() }
        }
        startListening()
    }

    private func loadDemo() {
        waitingCards = DemoData.replyCards.filter { $0.status == .waiting }
        handledCards = DemoData.replyCards.filter { $0.status != .waiting }
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
    }

    func refreshReplyCards() async {
        guard !session.isDemo else { return }
        do {
            async let waiting = session.api.replyCards(status: .waiting)
            async let answered = session.api.replyCards(status: .answered, limit: 20)
            async let expired = session.api.replyCards(status: .expired, limit: 10)
            async let counts = session.api.replyCardCounts()

            waitingCards = try await waiting.sorted { $0.createdTs < $1.createdTs }
            let handled = try await (answered + expired)
            handledCards = handled.sorted {
                ($0.answeredTs ?? $0.expiredTs ?? 0) > ($1.answeredTs ?? $1.expiredTs ?? 0)
            }
            cardCounts = try await counts
            await hydrateWaitingCards()
        } catch {
            note(error)
        }
    }

    /// Pull the body and options onto the waiting cards.
    ///
    /// `GET /api/reply-cards` returns a deliberately light row — the server's
    /// own note says the list carries no body and no options, they are one
    /// `get_reply_card` away. But the whole design rests on the inbox card being
    /// the decision surface ("選項就在卡上，零跳轉"), so the app has to fetch
    /// them. Only the cards actually waiting on the owner, capped, and
    /// best-effort: a card that fails to hydrate still shows its question and
    /// still opens.
    private func hydrateWaitingCards() async {
        let pending = waitingCards.prefix(hydrationLimit).filter { !$0.isDetailed }
        guard !pending.isEmpty else { return }

        let api = session.api
        let details = await withTaskGroup(of: ReplyCard?.self,
                                          returning: [String: ReplyCard].self) { group in
            for card in pending {
                let id = card.id
                group.addTask { try? await api.replyCard(id: id) }
            }
            var collected: [String: ReplyCard] = [:]
            for await detail in group {
                if let detail { collected[detail.id] = detail }
            }
            return collected
        }
        guard !details.isEmpty else { return }

        for (id, detail) in details { cardDetails[id] = detail }
        waitingCards = waitingCards.map { details[$0.id] ?? $0 }
    }

    /// Enough to cover an inbox a person could actually work through. Past this
    /// the owner is not deciding card by card anyway.
    private let hydrationLimit = 12

    /// The list endpoint omits `body`/`options`, so the single-card screen
    /// fetches the full card once and caches it.
    @discardableResult
    func loadCardDetail(_ id: String) async -> ReplyCard? {
        if let cached = cardDetails[id], cached.isDetailed { return cached }
        guard !session.isDemo else { return cardDetails[id] }
        do {
            let card = try await session.api.replyCard(id: id)
            cardDetails[id] = card
            return card
        } catch {
            note(error)
            return waitingCards.first { $0.id == id } ?? handledCards.first { $0.id == id }
        }
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
            self.members = try await members
            self.outsourceWorkers = try await workers
            self.unreadTotal = try await unread.unread
        } catch {
            note(error)
        }
    }

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
        await refreshReplyCards()
        await refreshTasks()
        await refreshOffice()
    }

    /// A delta is a hint, never data. Map the topic to the list it invalidates.
    private func apply(_ frame: EventFrame) async {
        switch frame.topic {
        case .replyCard:
            cardDetails.removeAll()
            await refreshReplyCards()
            await refreshTasks()
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
