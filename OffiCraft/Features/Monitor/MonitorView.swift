import SwiftUI

/// 監控 — accounts, machines, AI sessions.
///
/// On the phone this is cards, not a table: the console's grid does not survive
/// a 393pt width, and the questions you actually ask on a phone are "is an
/// account overheating" and "is a session about to hand over".
struct MonitorView: View {
    @Environment(StudioStore.self) private var store
    @Environment(AppSession.self) private var session

    @State private var tab: Tab = .accounts

    private enum Tab: Hashable, CaseIterable {
        case accounts, machines, sessions

        var title: String {
            switch self {
            case .accounts: return "帳號"
            case .machines: return "機器"
            case .sessions: return "AI 會話"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "監控")

            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { value in
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { tab = value }
                    } label: {
                        Text(value.title)
                            .font(.system(size: 13, weight: tab == value ? .semibold : .regular))
                            .foregroundStyle(tab == value ? OC.label : OC.labelTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(tab == value ? OC.surface2 : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OCMetrics.headerPadding)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(spacing: 12) {
                    switch tab {
                    case .accounts:
                        if store.monitoring.accounts.isEmpty {
                            EmptyStateView(icon: .monitor, title: "沒有帳號用量資料")
                        }
                        ForEach(store.monitoring.accounts) { AccountCard(account: $0) }
                    case .machines:
                        if store.monitoring.machines.isEmpty {
                            EmptyStateView(icon: .monitor, title: "沒有機器回報")
                        }
                        ForEach(store.monitoring.machines) { MachineCard(machine: $0) }
                    case .sessions:
                        if store.monitoring.sessions.isEmpty {
                            EmptyStateView(icon: .monitor, title: "目前沒有執行中的會話")
                        }
                        ForEach(store.monitoring.sessions) { agentSession in
                            SessionCard(session: agentSession,
                                        threshold: handoverThreshold,
                                        isOutsource: isOutsource(agentSession))
                        }
                    }
                }
                .padding(.horizontal, OCMetrics.screenPadding)
                .padding(.bottom, 24)
            }
            .refreshable { await store.refreshMonitoring() }
        }
        .background(OC.bg)
        .navigationBarHidden(true)
    }

    /// The automatic-handover threshold the session meters are read against.
    private var handoverThreshold: Double {
        session.isDemo ? DemoData.handoverThreshold : 0.75
    }

    private func isOutsource(_ agentSession: MonitorSession) -> Bool {
        store.outsourceWorkers.contains {
            $0.id == agentSession.id || $0.codename == agentSession.name
        }
    }
}

// MARK: - Account

private struct AccountCard: View {
    let account: MonitorAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 9) {
                Text(account.displayName)
                    .font(.ocBodyEmphasised)
                    .foregroundStyle(OC.label)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if account.isOverheated {
                    StatusChip(text: "過熱", tint: OC.overheat, showsDot: false)
                }
            }

            VStack(spacing: 6) {
                meter(title: "7 日視窗", window: account.sevenDay, emphasise: true)
                meter(title: "5 小時視窗", window: account.fiveHour, emphasise: false)
            }

            if let label = account.accountLabel, !label.isEmpty {
                Text("回報標籤原文 · \(label)")
                    .font(.ocCaption)
                    .foregroundStyle(OC.labelQuaternary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OC.surface)
        )
    }

    @ViewBuilder
    private func meter(title: String, window: UsageWindow?, emphasise: Bool) -> some View {
        let value = window?.pct ?? 0
        let hot = emphasise && value >= 0.8
        VStack(spacing: 5) {
            HStack {
                Text(title)
                    .font(.ocFootnoteSmall)
                    .foregroundStyle(OC.labelTertiary)
                Spacer()
                Text(OCFormat.percent(window?.pct))
                    .font(.system(size: 12.5, weight: hot ? .semibold : .regular))
                    .foregroundStyle(hot ? OC.overheat : OC.labelTertiary)
                    .monospacedDigit()
            }
            OCProgressBar(value: value, tint: hot ? OC.overheat : OC.accent)
        }
    }
}

// MARK: - Machine

private struct MachineCard: View {
    let machine: MonitorMachine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Circle()
                    .fill(machine.agents > 0 ? OC.accent : OC.labelQuaternary)
                    .frame(width: 8, height: 8)
                Text(machine.displayName)
                    .font(.ocBodyEmphasised)
                    .foregroundStyle(OC.label)
                Spacer(minLength: 6)
                Text(machine.activityLabel)
                    .font(.ocFootnoteSmall)
                    .foregroundStyle(OC.labelTertiary)
                if machine.hardwareStale == true {
                    StatusChip(text: "資料過期", tint: OC.labelTertiary, showsDot: false)
                }
            }

            // The wire reports percentages only, so the readout is percentages
            // rather than the mock's absolute "11.4／16 GB".
            HStack(spacing: 18) {
                if let cpu = machine.cpuPct {
                    Text("CPU \(OCFormat.percent(cpu))")
                }
                if let ram = machine.ramPct {
                    Text("RAM \(OCFormat.percent(ram))")
                }
                Text("\(machine.agents) sessions")
                if let battery = machine.batteryPct, machine.acPower != true {
                    Text("電量 \(OCFormat.percent(battery))")
                }
            }
            .font(.ocFootnoteSmall)
            .foregroundStyle(OC.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OC.surface)
        )
    }
}

// MARK: - Session

private struct SessionCard: View {
    let session: MonitorSession
    let threshold: Double
    var isOutsource: Bool

    private var contextValue: Double { session.contextPct ?? 0 }
    /// Past the threshold the session is about to hand over — worth flagging.
    private var nearHandover: Bool { contextValue >= threshold }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(session.name)
                    .font(.ocCalloutEmphasised)
                    .foregroundStyle(OC.label)
                Spacer(minLength: 6)
                if isOutsource {
                    StatusChip(text: "外包", tint: OC.external, showsDot: false)
                }
                if let model = session.model {
                    StatusChip(text: "\(model) \(session.effort.shortLabel)",
                               tint: nearHandover ? OC.waiting : OC.accent,
                               showsDot: false)
                }
            }

            if session.contextPct != nil {
                VStack(spacing: 5) {
                    HStack {
                        Text("記憶用量")
                            .font(.ocFootnoteSmall)
                            .foregroundStyle(OC.labelTertiary)
                        Spacer()
                        Text("\(OCFormat.percent(contextValue)) · 換手門檻 \(OCFormat.percent(threshold))")
                            .font(.ocFootnoteSmall)
                            .foregroundStyle(nearHandover ? OC.waiting : OC.labelTertiary)
                    }
                    OCProgressBar(value: contextValue,
                                  tint: nearHandover ? OC.waiting : OC.memory)
                }
            }

            Text(footnote)
                .font(.ocCaption)
                .foregroundStyle(OC.labelQuaternary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OC.surface)
        )
    }

    private var footnote: String {
        var parts: [String] = []
        if let model = session.model { parts.append(model) }
        if let machine = session.machine { parts.append(machine) }
        if let account = session.account { parts.append(account) }
        return parts.joined(separator: " · ")
    }
}
