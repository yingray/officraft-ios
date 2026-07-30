import SwiftUI

/// iPad shell: sidebar → list → detail.
///
/// The point of the three columns is that a decision never costs the list: you
/// pick on the left, scan in the middle, and decide on the right.
struct SplitRootView: View {
    @Binding var section: AppSection

    @Environment(StudioStore.self) private var store
    @Environment(AppSession.self) private var session

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var columnVisibilityBeforeDetailOnly: NavigationSplitViewVisibility = .all
    @State private var visibilityRequestGeneration = 0
    @State private var selectedCardId: String?
    @State private var selectedTaskId: String?
    @State private var selectedPeerId: String?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } content: {
            middleColumn
        } detail: {
            detailPane
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                BrandMark(size: 26)
                Text(studioName)
                    .font(.ocCalloutEmphasised)
                    .foregroundStyle(OC.label)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    requestColumnVisibility(.doubleColumn)
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OC.labelSecondary)
                        .frame(
                            minWidth: OCMetrics.minTapTarget,
                            minHeight: OCMetrics.minTapTarget
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收合側邊欄")
                .accessibilityHint("隱藏最左欄，保留清單與明細")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 14)

            ForEach(AppSection.allCases) { item in
                sidebarRow(item)
            }

            Spacer()

            HStack(spacing: 10) {
                Icon(.user, size: 15)
                    .foregroundStyle(OC.accent)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(OC.accentFill)
                    )
                Text(ownerName)
                    .font(.ocSubhead)
                    .foregroundStyle(OC.label)
                Spacer()
                Button {
                    section = .more
                } label: {
                    Icon(.settings, size: 15).foregroundStyle(OC.labelTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(OC.surface)
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .background(OC.bgElevated)
        .navigationBarHidden(true)
        .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 260)
    }

    private var studioName: String {
        session.isDemo ? DemoData.studioName : (session.activeHost?.display ?? "OffiCraft")
    }

    private var ownerName: String {
        session.isDemo ? DemoData.ownerName : "Owner"
    }

    private func sidebarRow(_ item: AppSection) -> some View {
        let isSelected = section == item
        return Button {
            section = item
            clearSelection()
        } label: {
            HStack(spacing: 11) {
                Icon(item.icon, size: 15)
                    .foregroundStyle(isSelected ? OC.accent : OC.labelTertiary)
                Text(item.title)
                    .font(isSelected ? .ocCalloutEmphasised : .ocCallout)
                    .foregroundStyle(isSelected ? OC.accent : OC.labelSecondary)
                Spacer(minLength: 4)
                if let count = badge(for: item), count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(item == .asks ? .white : OC.labelSecondary)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(
                            Capsule().fill(item == .asks ? OC.badge : OC.surface2)
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: OCMetrics.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(isSelected ? OC.accentFill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badge(for item: AppSection) -> Int? {
        switch item {
        case .asks: return store.waitingCardCount
        case .tasks: return store.openTasks.count
        case .office: return store.unreadTotal
        default: return nil
        }
    }

    private func clearSelection() {
        selectedCardId = nil
        selectedTaskId = nil
        selectedPeerId = nil
    }

    // MARK: Middle column

    @ViewBuilder
    private var middleColumn: some View {
        Group {
            switch section {
            case .asks: AskListColumn(selection: $selectedCardId)
            case .tasks: TaskListColumn(selection: $selectedTaskId)
            case .office: OfficeListColumn(selection: $selectedPeerId)
            case .monitor: NavigationStack { MonitorView() }
            case .more: NavigationStack { MoreView() }
            }
        }
        .navigationSplitViewColumnWidth(min: 300, ideal: 330, max: 380)
        .safeAreaInset(edge: .top, spacing: 0) {
            if columnVisibility != .all {
                HStack {
                    Button {
                        requestColumnVisibility(.all)
                    } label: {
                        Label("顯示側邊欄", systemImage: "sidebar.left")
                            .font(.ocSubhead.weight(.semibold))
                            .foregroundStyle(OC.accent)
                            .frame(minHeight: OCMetrics.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("顯示側邊欄")
                    .accessibilityHint("還原最左欄")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .background(OC.bg)
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
    }

    // MARK: Detail

    private var detailPane: some View {
        VStack(spacing: 0) {
            if hasSelectedDetail {
                HStack {
                    Spacer()
                    Button {
                        if columnVisibility == .detailOnly {
                            exitDetailOnly()
                        } else {
                            enterDetailOnly()
                        }
                    } label: {
                        Label(
                            columnVisibility == .detailOnly ? "退出全螢幕" : "全螢幕",
                            systemImage: columnVisibility == .detailOnly
                                ? "arrow.down.right.and.arrow.up.left"
                                : "arrow.up.left.and.arrow.down.right"
                        )
                        .font(.ocSubhead.weight(.semibold))
                        .foregroundStyle(OC.accent)
                        .frame(minHeight: OCMetrics.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        columnVisibility == .detailOnly ? "退出明細全螢幕" : "展開明細全螢幕"
                    )
                    .accessibilityHint(
                        columnVisibility == .detailOnly
                            ? "還原進入全螢幕前的欄位"
                            : "暫時隱藏側邊欄與清單"
                    )
                }
                .padding(.horizontal, 16)
                .background(OC.bg)
                .overlay(alignment: .bottom) { Hairline() }
            }

            // Key the whole detail stack, not each destination's loading task.
            // The selection owns this lifetime; column visibility does not, so
            // entering and leaving full screen preserves the current content.
            NavigationStack { detailColumn }
                .id(detailIdentity)
        }
        .background(OC.bg)
        .onChange(of: hasSelectedDetail) { _, hasSelectedDetail in
            if !hasSelectedDetail, columnVisibility == .detailOnly {
                exitDetailOnly()
            }
        }
    }

    private func enterDetailOnly() {
        columnVisibilityBeforeDetailOnly =
            columnVisibility == .doubleColumn ? .doubleColumn : .all
        requestColumnVisibility(.detailOnly)
    }

    private func exitDetailOnly() {
        let requestGeneration = beginVisibilityRequest()
        guard columnVisibilityBeforeDetailOnly == .all else {
            columnVisibility = .doubleColumn
            return
        }

        // NavigationSplitView normalizes a single detail-only → all write to
        // double-column. Give each native value its own render pass, then
        // reassert all without waiting for a framework callback.
        columnVisibility = .doubleColumn
        Task { @MainActor in
            await Task.yield()
            await Task.yield()
            guard requestGeneration == visibilityRequestGeneration else { return }
            columnVisibility = .all
        }
    }

    private func requestColumnVisibility(_ visibility: NavigationSplitViewVisibility) {
        beginVisibilityRequest()
        columnVisibility = visibility
    }

    @discardableResult
    private func beginVisibilityRequest() -> Int {
        visibilityRequestGeneration &+= 1
        return visibilityRequestGeneration
    }

    private var hasSelectedDetail: Bool {
        switch section {
        case .asks: return selectedCardId != nil
        case .tasks: return selectedTaskId != nil
        case .office: return selectedPeerId != nil
        case .monitor, .more: return false
        }
    }

    private var detailIdentity: IPadSplitDetailIdentity {
        switch section {
        case .asks:
            return IPadSplitDetailIdentity(kind: .ask, itemID: selectedCardId)
        case .tasks:
            return IPadSplitDetailIdentity(kind: .task, itemID: selectedTaskId)
        case .office:
            return IPadSplitDetailIdentity(kind: .peer, itemID: selectedPeerId)
        case .monitor:
            return IPadSplitDetailIdentity(kind: .monitor, itemID: nil)
        case .more:
            return IPadSplitDetailIdentity(kind: .more, itemID: nil)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        switch section {
        case .asks:
            if let selectedCardId {
                AskDetailView(cardId: selectedCardId)
            } else {
                placeholder(icon: .inbox, text: "從左邊挑一張請示")
            }
        case .tasks:
            if let selectedTaskId {
                TaskDetailView(taskId: selectedTaskId)
            } else {
                placeholder(icon: .tasks, text: "從左邊挑一個任務")
            }
        case .office:
            if let selectedPeerId {
                ChatView(peerId: selectedPeerId)
            } else {
                placeholder(icon: .office, text: "從左邊挑一位成員")
            }
        case .monitor, .more:
            placeholder(icon: section.icon, text: section.title)
        }
    }

    private func placeholder(icon: OCIcon, text: String) -> some View {
        VStack {
            EmptyStateView(icon: icon, title: text)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OC.bg)
    }
}

// MARK: - Ask column

private struct AskListColumn: View {
    @Binding var selection: String?
    @Environment(StudioStore.self) private var store
    @State private var tab: Tab = .waiting

    private enum Tab: Hashable { case waiting, handled }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                Text("請示").font(.ocTitle2).foregroundStyle(OC.label)
                Spacer()
                Text("篩選").font(.ocSubhead).foregroundStyle(OC.accent)
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 10)

            SegmentedTabs(
                items: [
                    .init(value: Tab.waiting, title: "待回覆 \(store.waitingCardCount)"),
                    .init(value: Tab.handled, title: "已處理 \(store.handledCardCount)"),
                ],
                selection: $tab
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    let cards = tab == .waiting ? store.waitingCards : store.handledCards
                    ForEach(cards) { card in
                        CompactAskRow(card: card, isSelected: card.id == selection) {
                            selection = card.id
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        // Same rule as the iPhone inbox: the handled panes are fetched when
        // this tab is opened, not at launch.
        .task(id: tab) {
            if tab == .handled { await store.refreshHandledCards() }
        }
        .onChange(of: store.replyCardRevision) {
            if tab == .handled { Task { await store.refreshHandledCards() } }
        }
    }
}

private struct CompactAskRow: View {
    let card: ReplyCard
    let isSelected: Bool
    var onSelect: () -> Void

    @Environment(StudioStore.self) private var store

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Avatar(name: store.displayName(for: card.from), id: card.from, size: 26)
                    Text(store.displayName(for: card.from))
                        .font(.ocSubhead.weight(.semibold))
                        .foregroundStyle(OC.label)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if card.status == .waiting {
                        Text(OCFormat.duration(card.waitedFor()))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(OC.waiting)
                    } else {
                        StatusChip(text: card.status.label, tint: card.status.tint, showsDot: false)
                    }
                }

                Text(MarkdownParser.inline(card.summary))
                    .font(.ocSubhead.weight(.semibold))
                    .foregroundStyle(OC.label)
                    .lineSpacing(3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let attachments = card.attachments, !attachments.isEmpty {
                    Text("附 \(attachments.map(\.filename).joined(separator: "、"))")
                        .font(.ocFootnoteSmall)
                        .foregroundStyle(OC.labelTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: OCMetrics.compactCardRadius, style: .continuous)
                    .fill(OC.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: OCMetrics.compactCardRadius, style: .continuous)
                            .strokeBorder(isSelected ? OC.accentBorder : OC.hairline, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Task column

private struct TaskListColumn: View {
    @Binding var selection: String?
    @Environment(StudioStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Text("任務")
                .font(.ocTitle2)
                .foregroundStyle(OC.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.openTasks) { task in
                        Button {
                            selection = task.id
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack(spacing: 6) {
                                    TaskNumberChip(taskNo: task.taskNo, showsIcon: false)
                                    StatusChip(text: task.status.label, tint: task.status.tint)
                                    Spacer(minLength: 0)
                                }
                                Text(task.title)
                                    .font(.ocSubhead.weight(.semibold))
                                    .foregroundStyle(OC.label)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 10) {
                                    OCProgressBar(value: task.progress, tint: task.status.tint)
                                    Text(task.progressLabel)
                                        .font(.ocCaptionSmall)
                                        .foregroundStyle(OC.labelTertiary)
                                        .fixedSize()
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: OCMetrics.compactCardRadius, style: .continuous)
                                    .fill(OC.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OCMetrics.compactCardRadius, style: .continuous)
                                            .strokeBorder(
                                                task.id == selection ? OC.accentBorder : OC.hairline,
                                                lineWidth: 1
                                            )
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(OC.bg)
        .navigationBarHidden(true)
    }
}

// MARK: - Office column

private struct OfficeListColumn: View {
    @Binding var selection: String?
    @Environment(StudioStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Text("辦公室")
                .font(.ocTitle2)
                .foregroundStyle(OC.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.membersByChatRecency) { member in
                        peerRow(id: member.id, name: member.name,
                                subtitle: member.roleName, presence: member.presence,
                                unread: member.unreadCount)
                    }
                    if !store.outsourceWorkers.isEmpty {
                        Text("外包 OUTSOURCE")
                            .ocSectionLabel()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 10)
                            .padding(.leading, 4)
                    }
                    ForEach(store.workersByChatRecency) { worker in
                        peerRow(id: worker.id, name: worker.codename,
                                subtitle: worker.taskTitle ?? "待命",
                                presence: worker.presence, unread: worker.unreadCount)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(OC.bg)
        .navigationBarHidden(true)
    }

    private func peerRow(id: String, name: String, subtitle: String,
                         presence: Presence, unread: Int) -> some View {
        Button {
            selection = id
        } label: {
            HStack(spacing: 10) {
                Avatar(name: name, id: id, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.ocSubhead.weight(.semibold))
                            .foregroundStyle(OC.label)
                        PresenceDot(presence: presence, size: 6)
                    }
                    Text(subtitle)
                        .font(.ocCaption)
                        .foregroundStyle(OC.labelTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if unread > 0 { UnreadDot(size: 9) }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: OCMetrics.compactCardRadius, style: .continuous)
                    .fill(OC.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: OCMetrics.compactCardRadius, style: .continuous)
                            .strokeBorder(id == selection ? OC.accentBorder : OC.hairline, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
