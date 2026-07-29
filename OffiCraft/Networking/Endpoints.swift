import Foundation

// The slice of `spec/openapi.json` this cockpit needs. Each method maps 1:1 to
// an endpoint so the call sites read like the API docs.
extension APIClient {

    // MARK: Auth

    struct LoginRequest: Encodable { let password: String }
    struct ChangePasswordRequest: Encodable {
        let oldPassword: String
        let newPassword: String
    }

    func login(password: String) async throws -> LoginResponse {
        try await post("/api/login", body: LoginRequest(password: password))
    }

    func authStatus() async throws -> AuthStatus {
        try await get("/api/auth/status")
    }

    func changePassword(old: String, new: String) async throws {
        try await send("/api/auth/change-password",
                       method: "POST",
                       body: ChangePasswordRequest(oldPassword: old, newPassword: new))
    }

    /// Cheap round-trip used by 測試連線 and the health dot.
    func health() async throws {
        let _: EmptyResponse = try await get("/api/health")
    }

    func version() async throws -> ServerVersion {
        try await get("/api/version")
    }

    // MARK: Reply cards (請示)

    /// `status` is one of waiting / answered / expired; omitted returns all.
    func replyCards(status: ReplyCardStatus? = nil, limit: Int? = nil) async throws -> [ReplyCard] {
        var query: [String: String] = [:]
        if let status, status != .unknown { query["status"] = status.rawValue }
        if let limit { query["limit"] = String(limit) }
        return try await get("/api/reply-cards", query: query)
    }

    func replyCard(id: String) async throws -> ReplyCard {
        try await get("/api/reply-cards/\(id)")
    }

    func replyCardCounts() async throws -> ReplyCardCounts {
        try await get("/api/reply-cards/count")
    }

    /// Inline upload shape shared by chat, reply-card answers and cards.
    struct AttachmentUpload: Encodable {
        var filename: String?
        var mime: String?
        var dataB64: String

        init(filename: String?, mime: String?, data: Data) {
            self.filename = filename
            self.mime = mime
            self.dataB64 = data.base64EncodedString()
        }
    }

    struct AnswerRequest: Encodable {
        var optionIdx: Int?
        var text: String?
        var attachments: [AttachmentUpload]?
    }

    /// Answer a waiting card. `optionIdx` picks one of the offered options;
    /// `text` is the owner's own wording. Either may be present.
    @discardableResult
    func answer(cardId: String,
                optionIdx: Int?,
                text: String?,
                attachments: [AttachmentUpload]? = nil) async throws -> ReplyCard {
        try await post("/api/reply-cards/\(cardId)/answer",
                       body: AnswerRequest(optionIdx: optionIdx,
                                           text: text,
                                           attachments: attachments))
    }

    /// Revise an answer that was already given (PUT, not POST).
    @discardableResult
    func reviseAnswer(cardId: String, optionIdx: Int?, text: String?) async throws -> ReplyCard {
        try await sendJSON("/api/reply-cards/\(cardId)/answer",
                           method: "PUT",
                           body: AnswerRequest(optionIdx: optionIdx, text: text))
    }

    /// 標為過期 — the left-swipe action, behind a confirmation.
    func expire(cardId: String) async throws {
        try await send("/api/reply-cards/\(cardId)/expire",
                       method: "POST",
                       body: Optional<EmptyResponse>.none)
    }

    // MARK: Tasks

    /// `open: true` drops the terminal statuses (done / terminated / duplicated).
    func tasks(open: Bool? = nil,
               status: TaskStatus? = nil,
               executor: String? = nil,
               type: String? = nil) async throws -> [TaskSummary] {
        var query: [String: String] = [:]
        if let open { query["open"] = open ? "true" : "false" }
        if let status, status != .unknown { query["status"] = status.rawValue }
        if let executor { query["executor"] = executor }
        if let type { query["type"] = type }
        return try await get("/api/tasks", query: query)
    }

    func task(id: String) async throws -> TaskDetail {
        try await get("/api/tasks/\(id)")
    }

    func openTaskCount() async throws -> TaskCount {
        try await get("/api/tasks/count")
    }

    struct TaskMessageRequest: Encodable { let body: String }

    /// 傳訊息給 <executor> from the task detail screen.
    func sendTaskMessage(taskId: String, body: String) async throws {
        try await send("/api/tasks/\(taskId)/message",
                       method: "POST",
                       body: TaskMessageRequest(body: body))
    }

    struct PriorityRequest: Encodable { let priority: String }

    func setPriority(taskId: String, priority: TaskPriority) async throws {
        try await send("/api/tasks/\(taskId)/priority",
                       method: "POST",
                       body: PriorityRequest(priority: priority.rawValue))
    }

    // MARK: Office

    func members() async throws -> [Member] {
        try await get("/api/members")
    }

    func outsourceWorkers() async throws -> [OutsourceWorker] {
        try await get("/api/outsource-workers")
    }

    /// 喚醒 an offline member.
    func activate(memberId: String) async throws {
        try await send("/api/members/\(memberId)/activate",
                       method: "POST",
                       body: Optional<EmptyResponse>.none)
    }

    func deactivate(memberId: String) async throws {
        try await send("/api/members/\(memberId)/deactivate",
                       method: "POST",
                       body: Optional<EmptyResponse>.none)
    }

    // MARK: Chat

    func chat(with peer: String, limit: Int = 60, beforeTs: Double? = nil) async throws -> [ChatMessage] {
        var query = ["with": peer, "limit": String(limit)]
        if let beforeTs { query["before_ts"] = String(beforeTs) }
        return try await get("/api/chat", query: query)
    }

    /// The tail of the whole chat stream, every peer mixed together.
    ///
    /// The roster carries no "last message" timestamp — there is no such field
    /// on the wire — so the office list derives recency from this instead.
    func recentChat(limit: Int = 200) async throws -> [ChatMessage] {
        try await get("/api/chat", query: ["limit": String(limit)])
    }

    struct ChatSendRequest: Encodable {
        let to: String
        let body: String
        var attachments: [AttachmentUpload]?
    }

    @discardableResult
    func sendChat(to peer: String,
                  body: String,
                  attachments: [AttachmentUpload]? = nil) async throws -> ChatMessage {
        try await post("/api/chat",
                       body: ChatSendRequest(to: peer, body: body, attachments: attachments))
    }

    struct MarkReadRequest: Encodable { let peer: String }

    func markRead(peer: String) async throws {
        try await send("/api/chat/mark-read", method: "POST", body: MarkReadRequest(peer: peer))
    }

    func unreadCount() async throws -> UnreadCount {
        try await get("/api/chat/unread-count")
    }

    // MARK: Monitoring

    func monitoring() async throws -> MonitorSnapshot {
        try await get("/api/monitoring")
    }

    // MARK: Settings

    func settings() async throws -> StudioSettings {
        try await get("/api/settings")
    }

    @discardableResult
    func updateSettings(_ settings: StudioSettings) async throws -> StudioSettings {
        try await patch("/api/settings", body: settings)
    }

    // MARK: Push

    struct PushSubscription: Encodable {
        /// APNs device token, hex-encoded.
        let endpoint: String
        let platform: String
    }

    func registerPush(deviceToken: String) async throws {
        try await send("/api/push/subscription",
                       method: "POST",
                       body: PushSubscription(endpoint: deviceToken, platform: "apns"))
    }
}

// MARK: - PUT support

extension APIClient {
    /// `send(_:method:body:)` discards the response; the revise-answer endpoint
    /// returns the updated card, so it needs a decoding variant.
    func sendJSON<T: Decodable, Body: Encodable>(
        _ path: String,
        method: String,
        body: Body
    ) async throws -> T {
        try await request(path, method: method, body: body)
    }
}
