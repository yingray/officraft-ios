import Foundation

// Wire models for the OffiCraft server (`spec/openapi.json`).
// The decoder is configured with `.convertFromSnakeCase`, so property names are
// the camelCase form of the wire field. Anything the server may omit is
// optional — the cockpit is a long-lived client against a moving server.

// MARK: - Attachments

struct Attachment: Codable, Identifiable, Hashable {
    let id: String
    var filename: String = ""
    var mime: String = ""
    var isImage: Bool = false
    /// Server-relative path; resolve against the host before loading.
    var url: String = ""

    var isMarkdown: Bool {
        mime == "text/markdown" || filename.lowercased().hasSuffix(".md")
    }

    /// Files we can render in-app. Everything else goes to Quick Look.
    var opensInApp: Bool { isImage || isMarkdown }
}

// MARK: - Reply cards (請示)

struct ReplyCardAnswer: Codable, Hashable {
    var optionIdx: Int?
    var text: String?
    var attachments: [Attachment]?
}

struct TaskRef: Codable, Hashable {
    let id: String
    var title: String = ""
    var typeKey: String = ""
}

struct ReplyCard: Codable, Identifiable, Hashable {
    let id: String
    /// Member id of the asker.
    var from: String = ""
    var kind: String = ""
    var status: ReplyCardStatus = .waiting
    /// One-line question shown in the inbox.
    var summary: String = ""
    /// Full markdown body — only present on the single-card fetch.
    var body: String?
    var options: [String]?
    var attachments: [Attachment]?
    var answer: ReplyCardAnswer?
    var task: TaskRef?
    var chatMessageId: String?

    var createdTs: Double = 0
    var answeredTs: Double?
    var expiredTs: Double?

    var createdAt: Date { Date(timeIntervalSince1970: createdTs) }
    var answeredAt: Date? { answeredTs.map(Date.init(timeIntervalSince1970:)) }
    var expiredAt: Date? { expiredTs.map(Date.init(timeIntervalSince1970:)) }

    /// How long the owner has kept this card waiting.
    func waitedFor(now: Date = .now) -> TimeInterval {
        max(0, now.timeIntervalSince(createdAt))
    }

    /// The list-level card omits `body`/`options`; the detail fetch fills them.
    var isDetailed: Bool { body != nil || options != nil }
}

// MARK: - Tasks

struct TaskStep: Codable, Identifiable, Hashable {
    let id: String
    var taskId: String = ""
    var name: String = ""
    /// 完成準則 — definition of done.
    var dod: String?
    var status: StepStatus = .pending
    var orderIdx: Int = 0
    /// A gate step blocks until the owner answers its reply card.
    var isGate: Bool = false
    var parallelGroup: String?
    var replyCardId: String?
    var replyCardStatus: ReplyCardStatus?
    var waitingReason: String?
    var startedTs: Double?
    var finishedTs: Double?
}

struct TaskArtifact: Codable, Identifiable, Hashable {
    let id: String
    var attachmentId: String?
    var filename: String = ""
    var label: String?
    var mime: String = ""
    var isImage: Bool = false
    var url: String = ""
    var kind: String = ""
    var createdBy: String = ""
    var createdTs: Double = 0

    var asAttachment: Attachment {
        Attachment(id: attachmentId ?? id, filename: filename, mime: mime, isImage: isImage, url: url)
    }
}

/// List row shape from `GET /api/tasks`.
struct TaskSummary: Codable, Identifiable, Hashable {
    let id: String
    var taskNo: String = ""
    var title: String = ""
    var typeKey: String = ""
    var status: TaskStatus = .notStarted
    var priority: TaskPriority = .mid
    var executorId: String = ""
    var executorKind: ExecutorKind = .member
    var creatorId: String = ""
    var progressDone: Int = 0
    var progressTotal: Int = 0
    var artifactCount: Int = 0
    var deps: [String]?
    var waitingReason: String?
    /// Non-empty while the task is being reassigned.
    var lock: String?
    var createdTs: Double = 0
    var updatedTs: Double = 0
    var closedTs: Double?

    var progress: Double {
        progressTotal > 0 ? Double(progressDone) / Double(progressTotal) : 0
    }

    var createdAt: Date { Date(timeIntervalSince1970: createdTs) }

    /// "步驟 5/8"
    var progressLabel: String { "步驟 \(progressDone)/\(progressTotal)" }

    var isReassigning: Bool { (lock ?? "").isEmpty == false }
}

/// Full shape from `GET /api/tasks/{id}`.
struct TaskDetail: Codable, Identifiable, Hashable {
    let id: String
    var taskNo: String = ""
    var title: String = ""
    var description: String?
    var typeKey: String = ""
    var status: TaskStatus = .notStarted
    var priority: TaskPriority = .mid
    var executorId: String = ""
    var executorKind: ExecutorKind = .member
    var creatorId: String = ""
    var progressDone: Int = 0
    var progressTotal: Int = 0
    var steps: [TaskStep]?
    var artifacts: [TaskArtifact]?
    var deps: [String]?
    var waitingReason: String?
    var handoverNote: String?
    var handoverNoteBy: String?
    var lock: String?
    var createdTs: Double = 0
    var updatedTs: Double = 0
    var closedTs: Double?

    var progress: Double {
        progressTotal > 0 ? Double(progressDone) / Double(progressTotal) : 0
    }

    var createdAt: Date { Date(timeIntervalSince1970: createdTs) }

    var orderedSteps: [TaskStep] {
        (steps ?? []).sorted { $0.orderIdx < $1.orderIdx }
    }

    var summary: TaskSummary {
        TaskSummary(
            id: id, taskNo: taskNo, title: title, typeKey: typeKey,
            status: status, priority: priority,
            executorId: executorId, executorKind: executorKind, creatorId: creatorId,
            progressDone: progressDone, progressTotal: progressTotal,
            artifactCount: artifacts?.count ?? 0, deps: deps,
            waitingReason: waitingReason, lock: lock,
            createdTs: createdTs, updatedTs: updatedTs, closedTs: closedTs
        )
    }
}

// MARK: - Members (辦公室)

struct Member: Codable, Identifiable, Hashable {
    let id: String
    var memberNo: String?
    var name: String = ""
    var roleKey: String = ""
    var roleName: String = ""
    var presence: Presence = .offline
    var desiredState: String?
    var machine: String?
    var model: String?
    var effort: Effort = .medium
    var unreadCount: Int = 0
    var avatarUrl: String?
    var rosterStatus: String?
    var kind: String?
    /// Populated by the cockpit from the task list — the roster row shows
    /// "工程師 · 正在做 #T-4f2a".
    var currentTaskNo: String?

    var isActive: Bool { (rosterStatus ?? "active") == "active" }
}

/// 外包 — an ad-hoc worker bound to one task.
struct OutsourceWorker: Codable, Identifiable, Hashable {
    let id: String
    var codename: String = ""
    var presence: Presence = .offline
    var status: String = ""
    var model: String?
    var effort: Effort = .medium
    var account: String?
    var machine: String?
    var contextPct: Double?
    var cost: Double?
    var unreadCount: Int = 0
    var avatarUrl: String?
    var taskId: String?
    var taskTitle: String?
    var taskStatus: String?
    var delegatedBy: String?
    var createdTs: Double = 0

    /// The roster shows the bound task's type; the API gives us the title only,
    /// so callers cross-reference the task list when they need `type_key`.
    var displayName: String { codename }
}

// MARK: - Chat

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: String
    var from: String = ""
    var to: String = ""
    var body: String = ""
    var ts: Double = 0
    var attachments: [Attachment]?
    /// Set when this message announced a reply card.
    var replyCardStatus: ReplyCardStatus?
    var meta: [String: AnyCodableValue]?

    var sentAt: Date { Date(timeIntervalSince1970: ts) }

    /// Owner-authored messages render as the right-hand bubble.
    func isOwn(ownerId: String) -> Bool { from == ownerId || from == "owner" }

    /// The reply-card id this message announced, if any.
    var replyCardId: String? {
        if case .string(let value) = meta?["reply_card_id"] { return value }
        return nil
    }
}

// MARK: - Monitoring

struct MonitorAccount: Codable, Identifiable, Hashable {
    var account: String = ""
    var accountLabel: String?
    var displayName: String = ""
    var machine: String = ""
    var cost: Double?
    var fiveHour: UsageWindow?
    var sevenDay: UsageWindow?

    var id: String { "\(account)@\(machine)" }

    /// 過熱 is the server's verdict, not a client-side cutoff: it compares
    /// spend against elapsed time (`PaceMarginPct`), which an absolute
    /// threshold cannot express. Only the 7-day window is ever painted hot,
    /// matching the web console.
    var isOverheated: Bool { sevenDay?.isHot == true }
}

struct MonitorMachine: Codable, Identifiable, Hashable {
    var machine: String = ""
    var displayName: String = ""
    var cpuPct: Double?
    var ramPct: Double?
    var agents: Int = 0
    var accounts: [String]?
    var batteryPct: Double?
    var acPower: Bool?
    var claudeVersion: String?
    var hardwareStale: Bool?

    var id: String { machine }

    /// The roster line reads 忙碌 / 待機 off the agent count.
    var activityLabel: String { agents > 0 ? "忙碌" : "待機" }

    // The wire carries these on a 0..100 scale; the UI works in fractions.
    var cpuFraction: Double? { cpuPct.map { $0 / 100 } }
    var ramFraction: Double? { ramPct.map { $0 / 100 } }
    var batteryFraction: Double? { batteryPct.map { $0 / 100 } }
}

struct MonitorSession: Codable, Identifiable, Hashable {
    let id: String
    var name: String = ""
    var role: String?
    var account: String?
    var machine: String?
    var model: String?
    var effort: Effort = .medium
    var presence: Presence = .offline
    /// Context window usage, 0..100 on the wire.
    var contextPct: Double?
    var cost: Double?
    var bankedCost: Double?
    var compactionCount: Int?

    var contextFraction: Double? { contextPct.map { $0 / 100 } }
}

struct MonitorSnapshot: Codable, Hashable {
    var accounts: [MonitorAccount] = []
    var machines: [MonitorMachine] = []
    var sessions: [MonitorSession] = []
}

// MARK: - Counts

struct ReplyCardCounts: Codable, Hashable {
    var waiting: Int = 0
    var answered: Int = 0
    var expired: Int = 0
}

struct TaskCount: Codable, Hashable {
    var open: Int = 0
}

struct UnreadCount: Codable, Hashable {
    var unread: Int = 0
}

// MARK: - Auth

struct LoginResponse: Codable {
    let token: String
    var tokenType: String = "Bearer"
    var ownerId: String = "owner"
    var expiresIn: Int = 0
}

struct AuthStatus: Codable {
    var passwordSet: Bool = false
}

struct ServerVersion: Codable {
    var version: String?
    var build: String?
}

// MARK: - Settings

struct StudioSettings: Codable, Hashable {
    var orgName: String?
    var ownerName: String?
    /// 換手門檻 — context percentage that triggers an automatic handover.
    var handoverThreshold: Double?
    /// 登入有效期 in days.
    var sessionDays: Int?
    var theme: String?
}

// MARK: - Loose JSON

/// Minimal `Any`-shaped decoder for the free-form `meta` bag on chat messages.
enum AnyCodableValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
