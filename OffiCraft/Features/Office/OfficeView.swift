import SwiftUI

/// 辦公室 — the roster. Who is awake, what they are on, who is waiting for you
/// to read something.
struct OfficeView: View {
    @Environment(StudioStore.self) private var store

    @State private var tab: Tab = .members
    @State private var search = ""
    @State private var openPeer: PeerRoute?
    @State private var openTask: TaskRoute?

    private enum Tab: Hashable { case members, outsource }

    private var filteredMembers: [Member] {
        let all = store.membersByChatRecency
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.roleName.localizedCaseInsensitiveContains(search)
        }
    }

    private var filteredWorkers: [OutsourceWorker] {
        let all = store.workersByChatRecency
        guard !search.isEmpty else { return all }
        return all.filter {
            $0.codename.localizedCaseInsensitiveContains(search)
                || ($0.taskTitle ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    // The tab dots read the whole group, not the filtered lists above — the
    // same collections the tab counts come from.
    private var membersHaveUnread: Bool {
        RosterUnread.groupHasUnread(store.activeMembers.map(\.unreadCount))
    }

    private var workersHaveUnread: Bool {
        RosterUnread.groupHasUnread(store.outsourceWorkers.map(\.unreadCount))
    }

    /// 外包 shows "in use / capacity", matching the console's roster header.
    private var busyWorkers: Int {
        store.outsourceWorkers.filter { $0.taskId?.isEmpty == false }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "辦公室") {
                Button {
                    // Hiring lives in the web console; the app points there.
                } label: {
                    Text("招攬")
                        .font(.ocCallout)
                        .foregroundStyle(OC.accent)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            searchField

            SegmentedTabs(
                items: [
                    .init(value: Tab.members, title: "正職 \(store.activeMembers.count)",
                          hasUnread: membersHaveUnread),
                    .init(value: Tab.outsource,
                          title: "外包 \(busyWorkers) / \(max(store.outsourceWorkers.count, busyWorkers))",
                          hasUnread: workersHaveUnread),
                ],
                selection: $tab
            )
            .padding(.horizontal, OCMetrics.headerPadding)
            .padding(.bottom, 12)

            roster
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        .navigationDestination(item: $openPeer) { route in
            ChatView(peerId: route.id)
        }
        .navigationDestination(item: $openTask) { route in
            TaskDetailView(taskId: route.id)
        }
        .refreshable { await store.refreshOffice() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Icon(.search, size: 17).foregroundStyle(OC.labelQuaternary)
            TextField("搜尋成員", text: $search)
                .font(.ocCallout)
                .foregroundStyle(OC.labelBody)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Icon(.close, size: 13).foregroundStyle(OC.labelQuaternary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(OC.surface)
        )
        .padding(.horizontal, OCMetrics.headerPadding)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var roster: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if tab == .members {
                    if filteredMembers.isEmpty {
                        EmptyStateView(icon: .office, title: "找不到成員")
                    }
                    ForEach(filteredMembers) { member in
                        MemberRow(member: member) {
                            openPeer = PeerRoute(id: member.id)
                        } onWake: {
                            Task { await store.wake(member: member) }
                        }
                    }
                } else {
                    if filteredWorkers.isEmpty {
                        EmptyStateView(
                            icon: .office,
                            title: "目前沒有外包",
                            message: "把一次性的事交出去時，成員會自己招一位外包。"
                        )
                    }
                    ForEach(filteredWorkers) { worker in
                        OutsourceRow(worker: worker) {
                            openPeer = PeerRoute(id: worker.id)
                        } onOpenTask: { taskId in
                            openTask = TaskRoute(id: taskId)
                        }
                    }
                }
            }
            .padding(.horizontal, OCMetrics.screenPadding)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Rows

private struct MemberRow: View {
    let member: Member
    var onOpen: () -> Void
    var onWake: () -> Void

    @Environment(StudioStore.self) private var store

    private var subtitle: String {
        var parts: [String] = []
        if !member.roleName.isEmpty { parts.append(member.roleName) }
        if let taskNo = store.currentTaskNo(for: member.id) {
            parts.append("正在做 #\(taskNo)")
        } else {
            parts.append(member.presence.label)
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        // Row taps and the 喚醒 button are siblings, not nested buttons — a
        // Button inside a Button does not reliably receive its own taps.
        HStack(spacing: 12) {
            Avatar(name: member.name, id: member.id,
                   imageURL: member.avatarUrl.flatMap(URL.init(string:)),
                   size: 42)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(member.name)
                        .font(.ocBody.weight(.semibold))
                        .foregroundStyle(OC.label)
                    PresenceDot(presence: member.presence)
                }
                Text(subtitle)
                    .font(.ocFootnote)
                    .foregroundStyle(OC.labelTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)

            // Dot and 喚醒 are siblings now. They used to be an if/else, so an
            // offline member with unread had no way to be woken from here.
            if member.unreadCount > 0 {
                UnreadDot()
            }
            if !member.presence.isAwake {
                Button(action: onWake) {
                    Text("喚醒")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(OC.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minHeight: OCMetrics.minTapTarget)
                        .background(Capsule().fill(OC.accentFill))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OC.surface)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

private struct OutsourceRow: View {
    let worker: OutsourceWorker
    var onOpen: () -> Void
    var onOpenTask: (String) -> Void

    @Environment(StudioStore.self) private var store

    private var subtitle: String? {
        guard let title = worker.taskTitle, !title.isEmpty else { return nil }
        if let taskId = worker.taskId,
           let task = store.tasks.first(where: { $0.id == taskId }),
           !task.typeKey.isEmpty {
            return "\(task.typeKey) · \(title)"
        }
        return title
    }

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: worker.codename, id: worker.id, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(worker.codename)
                        .font(.ocBody.weight(.semibold))
                        .foregroundStyle(OC.label)
                    PresenceDot(presence: worker.presence)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.ocFootnote)
                        .foregroundStyle(OC.labelTertiary)
                        .lineLimit(1)
                } else {
                    Text("待命 · \(worker.model ?? "—")")
                        .font(.ocFootnote)
                        .foregroundStyle(OC.labelTertiary)
                }
                if let taskId = worker.taskId,
                   let task = store.tasks.first(where: { $0.id == taskId }) {
                    Button { onOpenTask(taskId) } label: {
                        TaskNumberChip(taskNo: task.taskNo, showsIcon: false)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if worker.unreadCount > 0 {
                UnreadDot()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OC.surface)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}
