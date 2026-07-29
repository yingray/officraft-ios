import SwiftUI

/// 更多 — settings and preferences, as an iOS grouped list.
struct MoreView: View {
    @Environment(AppSession.self) private var session
    @Environment(StudioStore.self) private var store

    @State private var route: Route?

    private enum Route: String, Hashable, Identifiable {
        case connection, lockScreen, appearance, roles, manuals, tuning, docs
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "更多")

            ScrollView {
                VStack(spacing: 22) {
                    profileCard
                    notificationsSection
                    appearanceSection
                    studioSection
                    if session.isDemo { demoNotice }
                }
                .padding(.horizontal, OCMetrics.screenPadding)
                .padding(.bottom, 28)
            }
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        .navigationDestination(item: $route) { route in
            switch route {
            case .connection: ConnectionSettingsView()
            case .lockScreen: LockScreenDetailView()
            case .appearance: AppearanceView()
            case .roles, .manuals, .tuning, .docs:
                ConsoleOnlyView(title: title(for: route))
            }
        }
    }

    private func title(for route: Route) -> String {
        switch route {
        case .roles: return "角色誌"
        case .manuals: return "任務手冊"
        case .tuning: return "參數調整"
        case .docs: return "使用說明"
        default: return ""
        }
    }

    // MARK: Sections

    private var profileCard: some View {
        HStack(spacing: 12) {
            Icon(.user, size: 22)
                .foregroundStyle(OC.accent)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous).fill(OC.accentFill)
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(ownerName)
                    .font(.ocBodyLarge.weight(.semibold))
                    .foregroundStyle(OC.label)
                Text("\(studioName) · owner")
                    .font(.ocFootnote)
                    .foregroundStyle(OC.labelTertiary)
            }
            Spacer(minLength: 6)
            Icon(.chevronRight, size: 14).foregroundStyle(OC.labelQuaternary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OC.surface)
        )
    }

    private var ownerName: String {
        store.settings.ownerDisplayName ?? (session.isDemo ? DemoData.ownerName : "Owner")
    }

    private var studioName: String {
        store.settings.studioName
            ?? (session.isDemo ? DemoData.studioName : (session.activeHost?.display ?? "OffiCraft"))
    }

    private var notificationsSection: some View {
        @Bindable var bindableSession = session
        return GroupedSection(header: "通知 NOTIFICATIONS") {
            GroupedRow(title: "請示推播") {
                Toggle("", isOn: $bindableSession.askPushEnabled)
                    .labelsHidden()
                    .tint(OC.toggleOn)
                    .onChange(of: session.askPushEnabled) { session.savePreferences() }
            }
            GroupedRow(title: "任務完成通知") {
                Toggle("", isOn: $bindableSession.taskDonePushEnabled)
                    .labelsHidden()
                    .tint(OC.toggleOn)
                    .onChange(of: session.taskDonePushEnabled) { session.savePreferences() }
            }
            GroupedRow(title: "鎖定畫面顯示選項", isLast: true, trailing: {
                RowValue(text: session.lockScreenDetail.label)
            }, action: { route = .lockScreen })
        }
    }

    private var appearanceSection: some View {
        GroupedSection(header: "外觀與語言 APPEARANCE") {
            GroupedRow(title: "外觀", trailing: {
                RowValue(text: session.appearance.label)
            }, action: { route = .appearance })
            GroupedRow(title: "語言", trailing: {
                RowValue(text: "繁體中文", showsChevron: false)
            })
            GroupedRow(title: "主題", trailing: {
                RowValue(text: "辦公室", showsChevron: false)
            })
            GroupedRow(title: "連線與安全", isLast: true, trailing: {
                RowValue(text: session.activeHost?.display ?? "未設定", mono: true)
            }, action: { route = .connection })
        }
    }

    private var studioSection: some View {
        GroupedSection(header: "工作室 STUDIO") {
            GroupedRow(title: "角色誌", trailing: {
                Icon(.chevronRight, size: 13).foregroundStyle(OC.labelQuaternary)
            }, action: { route = .roles })
            GroupedRow(title: "任務手冊", trailing: {
                Icon(.chevronRight, size: 13).foregroundStyle(OC.labelQuaternary)
            }, action: { route = .manuals })
            GroupedRow(title: "參數調整", trailing: {
                RowValue(text: tuningSummary)
            }, action: { route = .tuning })
            GroupedRow(title: "使用說明", isLast: true, trailing: {
                Icon(.chevronRight, size: 13).foregroundStyle(OC.labelQuaternary)
            }, action: { route = .docs })
        }
    }

    /// "7 天 · 75%" — session lifetime and the automatic-handover threshold,
    /// both read from the studio's own settings.
    private var tuningSummary: String {
        let days = store.settings.sessionDays ?? 7
        return "\(days) 天 · \(OCFormat.percent(store.handoverFraction))"
    }

    private var demoNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("目前是示範資料")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(OC.accent)
            Text("這些成員、任務與請示都是設計稿裡的範例，沒有連上任何 server。")
                .font(.ocFootnoteSmall)
                .foregroundStyle(OC.labelTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button("連到真的工作室") { session.signOut() }
                .font(.ocFootnote.weight(.semibold))
                .foregroundStyle(OC.accent)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(OC.accentFill.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(OC.accentBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
        )
    }
}

// MARK: - Appearance

struct AppearanceView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            GroupedSection(footer: "跟隨系統時，控制台會隨 iOS 的深淺色設定切換。") {
                ForEach(Array(AppearancePreference.allCases.enumerated()), id: \.element) { index, option in
                    GroupedRow(
                        title: option.label,
                        isLast: index == AppearancePreference.allCases.count - 1,
                        trailing: {
                            if session.appearance == option {
                                Icon(.check, size: 15).foregroundStyle(OC.accent)
                            }
                        },
                        action: {
                            session.appearance = option
                            session.savePreferences()
                        }
                    )
                }
            }
            .padding(OCMetrics.screenPadding)
        }
        .background(OC.bg)
        .navigationTitle("外觀")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Lock screen detail

struct LockScreenDetailView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            GroupedSection(
                footer: "選「完整問題與選項」時，鎖定畫面就能直接決定；覺得內容敏感就改成摘要。"
            ) {
                ForEach(Array(LockScreenDetail.allCases.enumerated()), id: \.element) { index, option in
                    GroupedRow(
                        title: option.label,
                        isLast: index == LockScreenDetail.allCases.count - 1,
                        trailing: {
                            if session.lockScreenDetail == option {
                                Icon(.check, size: 15).foregroundStyle(OC.accent)
                            }
                        },
                        action: {
                            session.lockScreenDetail = option
                            session.savePreferences()
                        }
                    )
                }
            }
            .padding(OCMetrics.screenPadding)
        }
        .background(OC.bg)
        .navigationTitle("鎖定畫面顯示選項")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Console-only destinations

/// 角色誌 / 任務手冊 / 參數調整 / 使用說明 are authoring surfaces that the doc
/// keeps in the web console; the app says so rather than shipping a stub.
struct ConsoleOnlyView: View {
    let title: String
    @Environment(AppSession.self) private var session

    var body: some View {
        VStack(spacing: 16) {
            EmptyStateView(
                icon: .fileText,
                title: "\(title)在網頁控制台編輯",
                message: "這個 App 專注在決策與追蹤；編輯角色、手冊與參數請開控制台。"
            )
            if let host = session.activeHost, let url = host.baseURL {
                Link(destination: url) {
                    Text("開啟控制台")
                        .font(.ocCallout.weight(.semibold))
                        .foregroundStyle(OC.accent)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(OC.accentFill))
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(OC.bg)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
