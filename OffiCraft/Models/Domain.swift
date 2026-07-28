import SwiftUI

// MARK: - Task status (八態)
//
// Vocabulary is the server's, copied from `frontend/src/i18n/locales/zh.ts`.
// Every enum decodes leniently: a value the server adds later lands in
// `.unknown` instead of failing the whole response.

enum TaskStatus: String, Codable, Hashable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case waitingOwner = "waiting_owner"
    case waitingExternal = "waiting_external"
    case done
    case terminated
    case duplicated
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .notStarted: return "尚未執行"
        case .inProgress: return "進行中"
        case .waitingOwner: return "等我回覆"
        case .waitingExternal: return "等待外部"
        case .done: return "已完成"
        case .terminated: return "終止"
        case .duplicated: return "重複"
        case .unknown: return "—"
        }
    }

    var tint: Color {
        switch self {
        case .inProgress, .done: return OC.accent
        case .waitingOwner: return OC.waiting
        case .waitingExternal: return OC.external
        case .terminated: return OC.danger
        case .notStarted, .duplicated, .unknown: return OC.labelTertiary
        }
    }

    /// Terminal statuses drop out of the 未結束 filter.
    var isClosed: Bool {
        self == .done || self == .terminated || self == .duplicated
    }

    /// Only 等我回覆 is allowed to interrupt the owner (design doc semantic-colour rule).
    var interrupts: Bool { self == .waitingOwner }
}

enum TaskPriority: String, Codable, Hashable {
    case high, mid, low, frozen
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskPriority(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .high: return "高"
        case .mid: return "中"
        case .low: return "低"
        case .frozen: return "凍結"
        case .unknown: return "—"
        }
    }

    var tint: Color {
        switch self {
        case .high: return OC.danger
        case .mid: return OC.waiting
        case .low: return OC.labelTertiary
        case .frozen: return OC.frozen
        case .unknown: return OC.labelTertiary
        }
    }

    /// 低 renders without an outline in the mock — it is the quiet default.
    var isBordered: Bool { self != .low && self != .unknown }
}

enum StepStatus: String, Codable, Hashable {
    case pending
    case inProgress = "in_progress"
    case done
    case waitingOwner = "waiting_owner"
    case waitingExternal = "waiting_external"
    case superseded
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StepStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .pending: return "尚未執行"
        case .inProgress: return "進行中"
        case .done: return "已完成"
        case .waitingOwner: return "等我回覆"
        case .waitingExternal: return "等待外部"
        case .superseded: return "已取代"
        case .unknown: return "—"
        }
    }

    var tint: Color {
        switch self {
        case .done: return OC.accent
        case .inProgress: return OC.accent
        case .waitingOwner: return OC.waiting
        case .waitingExternal: return OC.external
        case .pending, .superseded, .unknown: return OC.labelTertiary
        }
    }

    /// Colour of the timeline node dot.
    var nodeTint: Color {
        switch self {
        case .done, .inProgress: return OC.accent
        case .waitingOwner: return OC.waiting
        case .waitingExternal: return OC.external
        case .pending, .superseded, .unknown: return Color(hex: 0x4A5060)
        }
    }
}

enum Presence: String, Codable, Hashable {
    case online, offline, waking, stopping, stopped
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Presence(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .online: return "線上"
        case .waking: return "喚醒中"
        case .stopping: return "收尾中"
        case .stopped, .offline: return "離線"
        case .unknown: return "—"
        }
    }

    var tint: Color {
        switch self {
        case .online: return OC.accent
        case .waking, .stopping: return OC.waiting
        case .offline, .stopped, .unknown: return Color(hex: 0x4A5060)
        }
    }

    var isAwake: Bool { self == .online || self == .waking }
}

enum ReplyCardStatus: String, Codable, Hashable {
    case waiting, answered, expired
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReplyCardStatus(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .waiting: return "等你回覆"
        case .answered: return "已回覆"
        case .expired: return "已過期"
        case .unknown: return "—"
        }
    }

    var tint: Color {
        switch self {
        case .waiting: return OC.waiting
        case .answered: return OC.success
        case .expired, .unknown: return OC.labelTertiary
        }
    }
}

enum Effort: String, Codable, Hashable {
    case low, medium, high
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Effort(rawValue: raw) ?? .unknown
    }

    /// The mock shows the bare word ("sonnet · 中"), not 「中投入」.
    var shortLabel: String {
        switch self {
        case .low: return "低"
        case .medium: return "中"
        case .high: return "高"
        case .unknown: return "—"
        }
    }

    var label: String {
        switch self {
        case .low: return "低投入"
        case .medium: return "中投入"
        case .high: return "高投入"
        case .unknown: return "—"
        }
    }
}

/// 正職 vs 外包 — drives the roster split and the avatar palette.
enum ExecutorKind: String, Codable, Hashable {
    case member
    case outsource = "outsource_worker"
    case owner
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ExecutorKind(rawValue: raw) ?? .unknown
    }

    var label: String {
        switch self {
        case .member: return "正職"
        case .outsource: return "外包"
        case .owner: return "我"
        case .unknown: return "—"
        }
    }
}
