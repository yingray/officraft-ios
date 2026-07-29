import Foundation

/// The sample studio from the design doc.
///
/// It exists for two reasons: the login screen offers a look around before you
/// have a host to point at, and it gives every screen a deterministic fixture
/// for previews. Timestamps are derived from "now" so the relative labels
/// ("已等你 42 分") stay truthful whenever the app is opened.
enum DemoData {

    static let ownerId = "owner"
    static let ownerName = "Seth"
    static let studioName = "Hardcore Studio"
    static let buildVersion = "v260728-0914-c73f543"

    private static func minutesAgo(_ minutes: Double) -> Double {
        Date().addingTimeInterval(-minutes * 60).timeIntervalSince1970
    }

    private static func hoursAgo(_ hours: Double) -> Double { minutesAgo(hours * 60) }
    private static func daysAgo(_ days: Double) -> Double { hoursAgo(days * 24) }

    // MARK: - Members

    static let members: [Member] = [
        Member(id: "m-kyle", memberNo: "M-1", name: "Kyle",
               roleKey: "engineer", roleName: "工程師",
               presence: .online, machine: "studio-mini", model: "opus",
               effort: .high, unreadCount: 4, rosterStatus: "active",
               currentTaskNo: "T-4f2a"),
        Member(id: "m-sasha", memberNo: "M-2", name: "Sasha",
               roleKey: "designer", roleName: "設計師",
               presence: .waking, machine: "studio-mini", model: "sonnet",
               effort: .medium, unreadCount: 0, rosterStatus: "active"),
        Member(id: "m-mira", memberNo: "M-3", name: "Mira",
               roleKey: "assistant", roleName: "助理",
               presence: .offline, machine: "studio-air", model: "sonnet",
               effort: .low, unreadCount: 0, rosterStatus: "active"),
        Member(id: "m-noah", memberNo: "M-4", name: "Noah",
               roleKey: "analyst", roleName: "分析師",
               presence: .online, machine: "studio-air", model: "sonnet",
               effort: .medium, unreadCount: 1, rosterStatus: "active"),
    ]

    static let outsourceWorkers: [OutsourceWorker] = [
        OutsourceWorker(id: "ow-7", codename: "O-7", presence: .online,
                        status: "working", model: "sonnet", effort: .medium,
                        account: "studio@hardcore.tech", machine: "studio-mini",
                        contextPct: 31, unreadCount: 0,
                        taskId: "t-91c7", taskTitle: "整理七月帳號用量報告",
                        taskStatus: "in_progress", delegatedBy: "m-mira",
                        createdTs: hoursAgo(5)),
        OutsourceWorker(id: "ow-3", codename: "O-3", presence: .offline,
                        status: "idle", model: "sonnet", effort: .low,
                        machine: "studio-air", unreadCount: 0,
                        createdTs: daysAgo(2)),
    ]

    /// Roster names by member id, for the "誰問的" line on reply cards.
    static func displayName(for id: String) -> String {
        if let member = members.first(where: { $0.id == id }) { return member.name }
        if let worker = outsourceWorkers.first(where: { $0.id == id }) { return "外包 \(worker.codename)" }
        if id == ownerId { return ownerName }
        return id
    }

    static func roleName(for id: String) -> String {
        if let member = members.first(where: { $0.id == id }) { return member.roleName }
        if outsourceWorkers.contains(where: { $0.id == id }) { return "自由代辦" }
        return ""
    }

    // MARK: - Attachments

    static let rolloutPlan = Attachment(
        id: "att-rollout", filename: "rollout-plan.md",
        mime: "text/markdown", isImage: false, url: "/api/chat/attachment/att-rollout"
    )
    static let usageChart = Attachment(
        id: "att-usage-chart", filename: "usage-chart.png",
        mime: "image/png", isImage: true, url: "/api/chat/attachment/att-usage-chart"
    )
    static let accountsShot = Attachment(
        id: "att-accounts", filename: "accounts.png",
        mime: "image/png", isImage: true, url: "/api/chat/attachment/att-accounts"
    )
    static let julyUsage = Attachment(
        id: "att-july-usage", filename: "july-usage.md",
        mime: "text/markdown", isImage: false, url: "/api/chat/attachment/att-july-usage"
    )
    static let measureReport = Attachment(
        id: "att-measure", filename: "measure-report.md",
        mime: "text/markdown", isImage: false, url: "/api/chat/attachment/att-measure"
    )

    /// Bodies for the markdown attachments the preview sheet opens.
    static let attachmentBodies: [String: String] = [
        "att-july-usage": julyUsageMarkdown,
        "att-measure": measureReportMarkdown,
        "att-rollout": rolloutPlanMarkdown,
    ]

    // MARK: - Reply cards (請示)

    static let replyCards: [ReplyCard] = [
        ReplyCard(
            id: "rc-1", from: "m-kyle", kind: "decision", status: .waiting,
            summary: "要不要把 `/api/tasks` 的全量拉取改成分頁？",
            body: paginationQuestion,
            options: ["先加分頁，預設 50 筆", "維持全量，改前端虛擬列表"],
            attachments: [],
            task: TaskRef(id: "t-4f2a", title: "重寫任務清單的資料流，改成分頁 + 游標", typeKey: "review-pr"),
            chatMessageId: "msg-kyle-3",
            createdTs: minutesAgo(42)
        ),
        ReplyCard(
            id: "rc-2", from: "ow-7", kind: "decision", status: .waiting,
            summary: "上線視窗要排哪一段？",
            body: rolloutQuestion,
            options: [
                "週三 02:00–04:00",
                "週五 19:00–22:00",
                "週六 09:00–12:00（值班減半）",
                "下週一 01:00–03:00",
                "拆兩段：先灰度 10%，隔日全量",
                "等結算週後再排",
            ],
            attachments: [rolloutPlan],
            task: TaskRef(id: "t-91c7", title: "整理七月帳號用量報告", typeKey: "weekly-report"),
            createdTs: minutesAgo(95)
        ),
        ReplyCard(
            id: "rc-3", from: "m-mira", kind: "decision", status: .waiting,
            summary: "這批雜項這週先動哪一件？",
            // Ten options on purpose: this is the fixture for the last rule —
            // the tail folds into 其他 5 個, and the card says out loud that the
            // list itself is the problem.
            body: "客戶那邊沒有指定順序，我把積著的都列出來了。\n\n每一件都是半天到一天，動一件其他就要往後。",
            options: [
                "補上匯出報表的欄位對齊",
                "把登入失敗的錯誤訊息講清楚",
                "客戶名單的搜尋加上模糊比對",
                "週報樣板換成新的視覺",
                "把過期通知的文案改軟一點",
                "附件上傳的大小上限拉到 50MB",
                "設定頁的說明文字重寫",
                "清掉舊版的匯入腳本",
                "把時區顯示統一成台北",
                "信件簽名檔補上職稱",
            ],
            createdTs: minutesAgo(12)
        ),
        ReplyCard(
            id: "rc-4", from: "m-sasha", kind: "decision", status: .answered,
            summary: "首頁的 hero 要不要改成雙欄？",
            body: "雙欄能一次帶到價值主張與截圖，但手機上會被迫壓縮成單欄。",
            options: ["改成雙欄", "保持單欄，改壓縮上下留白"],
            attachments: [usageChart, measureReport],
            answer: ReplyCardAnswer(optionIdx: 1, text: nil),
            createdTs: hoursAgo(2.4),
            answeredTs: hoursAgo(1.9)
        ),
        ReplyCard(
            id: "rc-5", from: "m-mira", kind: "decision", status: .expired,
            summary: "週報要不要一併寄給客戶？",
            body: "本週有兩個里程碑完成，客戶那邊也在追進度。",
            options: ["一併寄出", "只寄內部"],
            createdTs: hoursAgo(9),
            expiredTs: hoursAgo(7.5)
        ),
        ReplyCard(
            id: "rc-6", from: "m-kyle", kind: "decision", status: .answered,
            summary: "要不要先補 e2e 再合這支 PR？",
            options: ["先補 e2e", "先合，隔天補"],
            answer: ReplyCardAnswer(optionIdx: 0, text: nil),
            createdTs: hoursAgo(14),
            answeredTs: hoursAgo(13.2)
        ),
    ]

    static let replyCardCounts = ReplyCardCounts(waiting: 3, answered: 8, expired: 1)

    // MARK: - Tasks

    static let tasks: [TaskSummary] = [
        TaskSummary(id: "t-4f2a", taskNo: "T-4f2a",
                    title: "重寫任務清單的資料流，改成分頁 + 游標",
                    typeKey: "review-pr", status: .waitingOwner, priority: .high,
                    executorId: "m-kyle", executorKind: .member, creatorId: ownerId,
                    progressDone: 5, progressTotal: 8, artifactCount: 3,
                    waitingReason: "分頁策略要拍板",
                    createdTs: daysAgo(3.1), updatedTs: minutesAgo(42)),
        TaskSummary(id: "t-91c7", taskNo: "T-91c7",
                    title: "整理七月帳號用量報告",
                    typeKey: "weekly-report", status: .inProgress, priority: .mid,
                    executorId: "ow-7", executorKind: .outsource, creatorId: "m-mira",
                    progressDone: 2, progressTotal: 6, artifactCount: 2,
                    createdTs: hoursAgo(5), updatedTs: minutesAgo(18)),
        TaskSummary(id: "t-2d10", taskNo: "T-2d10",
                    title: "申請 App Store 開發者帳號驗證",
                    typeKey: "ops", status: .waitingExternal, priority: .low,
                    executorId: "m-mira", executorKind: .member, creatorId: ownerId,
                    progressDone: 1, progressTotal: 4, artifactCount: 0,
                    deps: ["t-77b1"],
                    waitingReason: "等 Apple 審核回覆，預計 2 個工作日",
                    createdTs: daysAgo(1.4), updatedTs: hoursAgo(6)),
        TaskSummary(id: "t-77b1", taskNo: "T-77b1",
                    title: "整理憑證上傳流程",
                    typeKey: "ops", status: .notStarted, priority: .low,
                    executorId: "m-mira", executorKind: .member, creatorId: ownerId,
                    progressDone: 0, progressTotal: 3, artifactCount: 0,
                    createdTs: daysAgo(1.4), updatedTs: daysAgo(1.4)),
        TaskSummary(id: "t-5b83", taskNo: "T-5b83",
                    title: "把設計稿的深淺色 token 對齊 theme.css",
                    typeKey: "design", status: .inProgress, priority: .mid,
                    executorId: "m-sasha", executorKind: .member, creatorId: ownerId,
                    progressDone: 3, progressTotal: 5, artifactCount: 1,
                    createdTs: daysAgo(0.6), updatedTs: minutesAgo(140)),
        TaskSummary(id: "t-1c04", taskNo: "T-1c04",
                    title: "客戶季度回覆信草稿",
                    typeKey: "writing", status: .waitingOwner, priority: .mid,
                    executorId: "m-mira", executorKind: .member, creatorId: ownerId,
                    progressDone: 2, progressTotal: 3, artifactCount: 1,
                    waitingReason: "語氣要定調",
                    createdTs: hoursAgo(3), updatedTs: minutesAgo(12)),
        TaskSummary(id: "t-9a55", taskNo: "T-9a55",
                    title: "把 conformance 套件接上 CI",
                    typeKey: "ci", status: .done, priority: .mid,
                    executorId: "m-kyle", executorKind: .member, creatorId: ownerId,
                    progressDone: 6, progressTotal: 6, artifactCount: 2,
                    createdTs: daysAgo(4), updatedTs: daysAgo(0.8),
                    closedTs: daysAgo(0.8)),
        TaskSummary(id: "t-3e21", taskNo: "T-3e21",
                    title: "舊版匯出腳本改寫",
                    typeKey: "refactor", status: .terminated, priority: .low,
                    executorId: "m-noah", executorKind: .member, creatorId: ownerId,
                    progressDone: 1, progressTotal: 5, artifactCount: 0,
                    createdTs: daysAgo(6), updatedTs: daysAgo(3),
                    closedTs: daysAgo(3)),
    ]

    static let taskDetails: [String: TaskDetail] = [
        "t-4f2a": TaskDetail(
            id: "t-4f2a", taskNo: "T-4f2a",
            title: "重寫任務清單的資料流，改成分頁 + 游標",
            description: paginationQuestion,
            typeKey: "review-pr", status: .waitingOwner, priority: .high,
            executorId: "m-kyle", executorKind: .member, creatorId: ownerId,
            progressDone: 5, progressTotal: 8,
            steps: [
                TaskStep(id: "s-1", taskId: "t-4f2a", name: "量測現況首屏成本",
                         dod: "400 張任務下有 before 數據並貼在卡上",
                         status: .done, orderIdx: 0,
                         startedTs: daysAgo(3.1), finishedTs: daysAgo(3.0)),
                TaskStep(id: "s-2", taskId: "t-4f2a", name: "盤點 wire 的 query 參數",
                         dod: "列出其他 consumer 依賴的 exact-match 欄位",
                         status: .done, orderIdx: 1,
                         startedTs: daysAgo(2.9), finishedTs: daysAgo(2.6)),
                TaskStep(id: "s-3", taskId: "t-4f2a", name: "分頁策略拍板",
                         dod: "owner 選定分頁或虛擬列表，並記錄理由",
                         status: .waitingOwner, orderIdx: 2, isGate: true,
                         replyCardId: "rc-1", replyCardStatus: .waiting,
                         startedTs: minutesAgo(42)),
                TaskStep(id: "s-4", taskId: "t-4f2a", name: "改 adapter 與 hook",
                         dod: "conformance 綠、SSE refetch 對齊游標",
                         status: .pending, orderIdx: 3),
                TaskStep(id: "s-5", taskId: "t-4f2a", name: "補 e2e 與回歸",
                         dod: "400 張任務下首屏 < 0.4s 並附 after 數據",
                         status: .pending, orderIdx: 4),
            ],
            artifacts: [
                TaskArtifact(id: "ta-1", attachmentId: "att-measure",
                             filename: "measure-report.md", label: "量測報告",
                             mime: "text/markdown", isImage: false,
                             url: "/api/chat/attachment/att-measure",
                             kind: "report", createdBy: "m-kyle",
                             createdTs: daysAgo(3.0)),
                TaskArtifact(id: "ta-2", attachmentId: "att-usage-chart",
                             filename: "first-paint.png", label: "首屏比較圖",
                             mime: "image/png", isImage: true,
                             url: "/api/chat/attachment/att-usage-chart",
                             kind: "chart", createdBy: "m-kyle",
                             createdTs: daysAgo(2.9)),
                TaskArtifact(id: "ta-3", attachmentId: "att-rollout",
                             filename: "wire-consumers.md", label: "consumer 盤點",
                             mime: "text/markdown", isImage: false,
                             url: "/api/chat/attachment/att-rollout",
                             kind: "note", createdBy: "m-kyle",
                             createdTs: daysAgo(2.6)),
            ],
            waitingReason: "分頁策略要拍板",
            createdTs: daysAgo(3.1), updatedTs: minutesAgo(42)
        ),
        "t-91c7": TaskDetail(
            id: "t-91c7", taskNo: "T-91c7",
            title: "整理七月帳號用量報告",
            description: "把兩個帳號、四台機器的 7 月 session 數與用量整理成一份可直接讀的報告。",
            typeKey: "weekly-report", status: .inProgress, priority: .mid,
            executorId: "ow-7", executorKind: .outsource, creatorId: "m-mira",
            progressDone: 2, progressTotal: 6,
            steps: [
                TaskStep(id: "s91-1", taskId: "t-91c7", name: "抓取 7 月 session 明細",
                         dod: "兩個帳號都有逐日數據", status: .done, orderIdx: 0,
                         startedTs: hoursAgo(5), finishedTs: hoursAgo(4.2)),
                TaskStep(id: "s91-2", taskId: "t-91c7", name: "算出 7 日與 5 小時視窗用量",
                         dod: "與控制台監控頁數字一致", status: .done, orderIdx: 1,
                         startedTs: hoursAgo(4.2), finishedTs: hoursAgo(3.1)),
                TaskStep(id: "s91-3", taskId: "t-91c7", name: "畫出分帳號用量圖",
                         dod: "圖上標出過熱門檻", status: .inProgress, orderIdx: 2,
                         startedTs: hoursAgo(3.1)),
                TaskStep(id: "s91-4", taskId: "t-91c7", name: "上線視窗拍板",
                         dod: "owner 選定視窗", status: .waitingOwner, orderIdx: 3,
                         isGate: true, replyCardId: "rc-2", replyCardStatus: .waiting),
                TaskStep(id: "s91-5", taskId: "t-91c7", name: "寫成報告並附建議",
                         dod: "含換手門檻調整建議", status: .pending, orderIdx: 4),
            ],
            artifacts: [
                TaskArtifact(id: "ta91-1", attachmentId: "att-july-usage",
                             filename: "july-usage.md", label: "七月用量報告",
                             mime: "text/markdown", isImage: false,
                             url: "/api/chat/attachment/att-july-usage",
                             kind: "report", createdBy: "ow-7",
                             createdTs: hoursAgo(1.1)),
                TaskArtifact(id: "ta91-2", attachmentId: "att-usage-chart",
                             filename: "usage-chart.png", label: "分帳號用量圖",
                             mime: "image/png", isImage: true,
                             url: "/api/chat/attachment/att-usage-chart",
                             kind: "chart", createdBy: "ow-7",
                             createdTs: hoursAgo(1.0)),
            ],
            createdTs: hoursAgo(5), updatedTs: minutesAgo(18)
        ),
        "t-2d10": TaskDetail(
            id: "t-2d10", taskNo: "T-2d10",
            title: "申請 App Store 開發者帳號驗證",
            description: "送出公司實體驗證資料，等 Apple 回覆。",
            typeKey: "ops", status: .waitingExternal, priority: .low,
            executorId: "m-mira", executorKind: .member, creatorId: ownerId,
            progressDone: 1, progressTotal: 4,
            steps: [
                TaskStep(id: "s2d-1", taskId: "t-2d10", name: "備齊登記資料",
                         dod: "掃描件齊全", status: .done, orderIdx: 0,
                         startedTs: daysAgo(1.4), finishedTs: daysAgo(1.2)),
                TaskStep(id: "s2d-2", taskId: "t-2d10", name: "送出驗證申請",
                         dod: "收到 Apple 受理信",
                         status: .waitingExternal, orderIdx: 1,
                         waitingReason: "等 Apple 審核回覆，預計 2 個工作日",
                         startedTs: hoursAgo(6)),
                TaskStep(id: "s2d-3", taskId: "t-2d10", name: "設定憑證與描述檔",
                         dod: "能簽出一個可安裝的 build",
                         status: .pending, orderIdx: 2),
            ],
            artifacts: [],
            deps: ["t-77b1"],
            waitingReason: "等 Apple 審核回覆，預計 2 個工作日",
            createdTs: daysAgo(1.4), updatedTs: hoursAgo(6)
        ),
    ]

    // MARK: - Chat

    static func chat(with peer: String) -> [ChatMessage] {
        switch peer {
        case "m-kyle": return kyleThread
        case "ow-7": return outsourceThread
        default:
            return [
                ChatMessage(id: "msg-\(peer)-1", from: peer, to: ownerId,
                            body: "有需要我先做的，隨時說。", ts: hoursAgo(3)),
            ]
        }
    }

    /// Every peer's thread at once — the demo stand-in for the server's whole
    /// chat stream, which is what the office list derives its ordering from.
    static var allChat: [ChatMessage] {
        let peers = members.map(\.id) + outsourceWorkers.map(\.id)
        return peers.flatMap { chat(with: $0) }
    }

    static let kyleThread: [ChatMessage] = [
        ChatMessage(id: "msg-kyle-1", from: ownerId, to: "m-kyle",
                    body: "先量現況再決定，把數據貼在卡上", ts: hoursAgo(1.2)),
        ChatMessage(id: "msg-kyle-own-2", from: ownerId, to: "m-kyle",
                    body: "這是上次那份上線計畫，順便對一下回滾點。",
                    ts: hoursAgo(1.1),
                    attachments: [rolloutPlan, usageChart, accountsShot]),
        // Agent-to-agent: the owner is on neither end, so these fold away until
        // asked for. Three in a row plus Sasha's reply is the doc's "4 則".
        ChatMessage(id: "msg-inter-1", from: "m-kyle", to: "m-sasha",
                    body: "清單改分頁後，hero 那邊的 skeleton 高度要一起調嗎？",
                    ts: minutesAgo(74)),
        ChatMessage(id: "msg-inter-2", from: "m-sasha", to: "m-kyle",
                    body: "要，我把 50 筆的骨架高度標在 spec 上了。",
                    ts: minutesAgo(72)),
        ChatMessage(id: "msg-inter-3", from: "m-kyle", to: "ow-3",
                    body: "量測腳本放在 `scripts/bench.ts`，跑完貼上來。",
                    ts: minutesAgo(70)),
        ChatMessage(id: "msg-inter-4", from: "ow-3", to: "m-kyle",
                    body: "收到，大概 20 分鐘後給你。",
                    ts: minutesAgo(69)),
        // Server-authored. `from` is the synthetic "system" sender, never a
        // roster id — the same shape the real server writes on a reassign.
        ChatMessage(id: "msg-sys-1", from: ChatLane.systemSenderId, to: "m-kyle",
                    body: "Kyle 記憶用量達 75%，已自動換手；接手者沿用同一 session 與任務 `#T-4f2a`。",
                    ts: minutesAgo(66),
                    meta: ["task_id": .string("t-4f2a")]),
        ChatMessage(id: "msg-sys-2", from: ChatLane.systemSenderId, to: "m-kyle",
                    body: "已量完 before 數據，等 owner 拍板分頁策略後再改 adapter。",
                    ts: minutesAgo(65),
                    meta: ["task_id": .string("t-4f2a")]),
        ChatMessage(id: "msg-kyle-2", from: "m-kyle", to: ownerId,
                    body: measureResultMarkdown, ts: minutesAgo(58),
                    attachments: [measureReport]),
        ChatMessage(id: "msg-kyle-3", from: "m-kyle", to: ownerId,
                    body: "要不要把 /api/tasks 的全量拉取改成分頁？",
                    ts: minutesAgo(42),
                    replyCardStatus: .waiting,
                    meta: ["reply_card_id": .string("rc-1")]),
    ]

    static let outsourceThread: [ChatMessage] = [
        ChatMessage(id: "msg-ow7-1", from: "ow-7", to: ownerId,
                    body: "報告與截圖都放上來了，點開看：",
                    ts: minutesAgo(102),
                    attachments: [usageChart, accountsShot, julyUsage]),
        ChatMessage(id: "msg-ow7-2", from: "ow-7", to: ownerId,
                    body: "上線視窗要選週三凌晨還是週五下班後？",
                    ts: minutesAgo(95),
                    replyCardStatus: .waiting,
                    meta: ["reply_card_id": .string("rc-2")]),
    ]

    // MARK: - Monitoring

    static let monitoring = MonitorSnapshot(
        accounts: [
            // 86% spent against 62% elapsed → the server would call this "hot".
            MonitorAccount(account: "seth@hardcore.tech",
                           accountLabel: "seth@hardcore.tech(Hardcore Studio)",
                           displayName: "seth@hardcore.tech",
                           machine: "studio-mini", cost: 41.8,
                           fiveHour: UsageWindow(usedPct: 41, elapsedPct: 55, pace: "ok"),
                           sevenDay: UsageWindow(usedPct: 86, elapsedPct: 62, pace: "hot")),
            MonitorAccount(account: "studio@hardcore.tech",
                           accountLabel: "studio@hardcore.tech(Hardcore Studio)",
                           displayName: "studio@hardcore.tech",
                           machine: "studio-air", cost: 12.3,
                           fiveHour: UsageWindow(usedPct: 18, elapsedPct: 55, pace: "ok"),
                           sevenDay: UsageWindow(usedPct: 39, elapsedPct: 62, pace: "ok")),
        ],
        machines: [
            MonitorMachine(machine: "studio-mini", displayName: "studio-mini",
                           cpuPct: 62, ramPct: 71, agents: 3,
                           accounts: ["seth@hardcore.tech"],
                           claudeVersion: "1.8.4"),
            MonitorMachine(machine: "studio-air", displayName: "studio-air",
                           cpuPct: 11, ramPct: 34, agents: 1,
                           accounts: ["studio@hardcore.tech"],
                           batteryPct: 78, acPower: false,
                           claudeVersion: "1.8.4"),
        ],
        sessions: [
            MonitorSession(id: "sess-kyle", name: "Kyle", role: "工程師",
                           account: "seth@hardcore.tech", machine: "studio-mini",
                           model: "opus", effort: .high, presence: .online,
                           contextPct: 54, cost: 18.2),
            MonitorSession(id: "sess-ow7", name: "O-7", role: "外包",
                           account: "studio@hardcore.tech", machine: "studio-mini",
                           model: "sonnet", effort: .medium, presence: .online,
                           contextPct: 31, cost: 3.4),
            MonitorSession(id: "sess-noah", name: "Noah", role: "分析師",
                           account: "studio@hardcore.tech", machine: "studio-air",
                           model: "sonnet", effort: .medium, presence: .online,
                           contextPct: 22, cost: 2.1),
        ]
    )

    /// The studio settings, in the server's own shape.
    static let settings = StudioSettings(
        tokenTtl: 7 * 86_400,
        handoverPct: 75,
        codexCompactionThreshold: 3,
        outsourceMaxParallel: 5,
        orgName: studioName,
        ownerName: ownerName,
        displayTheme: "office",
        displayLanguage: "zh-Hant"
    )

    // MARK: - Long-form bodies

    static let paginationQuestion = """
    現在清單刻意不帶 query 拉全量，篩選、分區、排序全在前端；單一 refetch 路徑很好維護，但任務數上去後首屏會慢。

    > [!NOTE]
    > wire 的 exact-match query params 目前留給其他 consumer，改動只影響前端這條路徑。

    - 400 張任務：首屏 1.2s、記憶體 +38MB
    - 分頁後 SSE refetch 要重新對齊游標

    ```go
    func ListTasks(q Query) []Task {
      if q.Limit == 0 { q.Limit = 50 }
      return store.Page(q)
    }
    ```
    """

    /// The doc's "Many options" example, verbatim: six candidate windows, four
    /// blocks of body, one attachment. It is the fixture that exercises the
    /// summary + 讀全文 layout.
    static let rolloutQuestion = """
    六個候選窗都已避開客戶尖峰時段（平日 09–18），差別只在值班人力與回滾餘裕。

    ### 值班與餘裕

    - 週三凌晨：值班 3 人最足，但隔天上午有客戶 demo
    - 週五下班後：回滾餘裕最大，出事要加班
    - 週末場：值班減半，只適合灰度

    > [!WARNING]
    > 8/2 之後進客戶結算週，任何視窗都要往後推兩週。
    """

    static let measureResultMarkdown = """
    ## 量測結果

    - 400 張任務：**首屏 1.24s**（p95）
    - JSON 解析佔 **61%**

    | 任務數 | 首屏 | 記憶體 |
    | --- | --- | --- |
    | 120 | 0.31s | 12MB |
    | 400 | 1.24s | 50MB |

    > [!WARNING]
    > 分頁後 SSE 增量必須帶游標，否則新任務會插錯頁。

    - [x] 量測 before
    - [ ] 改 adapter

    ```ts
    const { tasks, cursor } = await listTasks({
      limit: 50, after: cursor,
    })
    ```
    """

    static let julyUsageMarkdown = """
    # 七月帳號用量報告

    兩個帳號、四台機器，7 月共 **1,284** 個 session。其中 3 次觸發自動換手。

    > [!IMPORTANT]
    > seth@ 帳號 7 日視窗已達 86%，建議把長任務排到另一個帳號。

    ## 分帳號用量

    | 帳號 | session | 7 日 |
    | --- | --- | --- |
    | seth@ | 861 | 86% |
    | studio@ | 423 | 39% |

    - [x] 拆帳號分流
    - [ ] 調整自動換手門檻至 70%

    ```bash
    oc accounts usage --window 7d --json
    ```
    """

    static let measureReportMarkdown = """
    # 首屏量測報告

    在 120 / 400 / 800 三種任務量下各跑 20 次，取 p95。

    | 任務數 | 首屏 p95 | 記憶體峰值 |
    | --- | --- | --- |
    | 120 | 0.31s | 12MB |
    | 400 | 1.24s | 50MB |
    | 800 | 2.61s | 96MB |

    > [!NOTE]
    > 記憶體是 renderer process 的峰值，不含圖片快取。

    JSON 解析佔了 61%，其次是首次排序 22%。
    """

    static let rolloutPlanMarkdown = """
    # 上線計畫

    ## 步驟

    1. 先開 feature flag，只對 owner 生效
    2. 觀察 30 分鐘的 SSE 游標對齊
    3. 全量開啟

    ## 回滾點

    - [x] flag 可即時關閉
    - [ ] 游標欄位需要 server 重啟才會退回

    > [!CAUTION]
    > 第 3 步之後回滾要重啟 server，會斷所有 SSE 連線。
    """
}
