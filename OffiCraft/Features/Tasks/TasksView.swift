import SwiftUI

/// 任務 — progress-oriented list. One row says which step a task is on and what
/// it is waiting for.
struct TasksView: View {
    @Environment(StudioStore.self) private var store

    @State private var filter: Filter = .open
    @State private var openTask: TaskRoute?
    @State private var openCard: CardRoute?
    @State private var typeFilter: String?
    @State private var executorFilter: String?

    enum Filter: Hashable { case open, waitingOwner, closed }

    private var visibleTasks: [TaskSummary] {
        var tasks: [TaskSummary]
        switch filter {
        case .open: tasks = store.openTasks
        case .waitingOwner: tasks = store.tasksWaitingOnOwner
        case .closed: tasks = store.closedTasks
        }
        if let typeFilter { tasks = tasks.filter { $0.typeKey == typeFilter } }
        if let executorFilter { tasks = tasks.filter { $0.executorId == executorFilter } }
        return tasks
    }

    private var allTypes: [String] {
        Array(Set(store.tasks.map(\.typeKey))).filter { !$0.isEmpty }.sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "任務") {
                filterMenu
            }

            FilterChipRow(
                items: [
                    .init(value: Filter.open, title: "未結束 \(store.openTasks.count)"),
                    .init(value: Filter.waitingOwner,
                          title: "等我回覆 \(store.tasksWaitingOnOwner.count)",
                          tint: OC.waiting),
                    .init(value: Filter.closed, title: "已結束"),
                ],
                selection: $filter
            )
            .padding(.bottom, 12)

            if typeFilter != nil || executorFilter != nil {
                activeFilterRow
            }

            list
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        .navigationDestination(item: $openTask) { route in
            TaskDetailView(taskId: route.id)
        }
        .navigationDestination(item: $openCard) { route in
            AskDetailView(cardId: route.id)
        }
        .refreshable { await store.refreshTasks() }
    }

    // MARK: Filters

    private var filterMenu: some View {
        Menu {
            Menu("任務類型") {
                Button("全部") { typeFilter = nil }
                ForEach(allTypes, id: \.self) { type in
                    Button(type) { typeFilter = type }
                }
            }
            Menu("負責人") {
                Button("全部") { executorFilter = nil }
                ForEach(store.activeMembers) { member in
                    Button(member.name) { executorFilter = member.id }
                }
                ForEach(store.outsourceWorkers) { worker in
                    Button("外包 \(worker.codename)") { executorFilter = worker.id }
                }
            }
            if typeFilter != nil || executorFilter != nil {
                Divider()
                Button("清除篩選", role: .destructive) {
                    typeFilter = nil
                    executorFilter = nil
                }
            }
        } label: {
            Text("篩選")
                .font(.ocCallout)
                .foregroundStyle(OC.accent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
    }

    private var activeFilterRow: some View {
        HStack(spacing: 8) {
            if let typeFilter {
                StatusChip(text: typeFilter, tint: OC.taskType)
            }
            if let executorFilter {
                StatusChip(text: store.displayName(for: executorFilter),
                           tint: OC.taskNo, showsDot: false)
            }
            Button("清除") {
                typeFilter = nil
                executorFilter = nil
            }
            .font(.ocFootnote)
            .foregroundStyle(OC.labelTertiary)
            Spacer()
        }
        .padding(.horizontal, OCMetrics.headerPadding)
        .padding(.bottom, 10)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if visibleTasks.isEmpty {
            ScrollView {
                EmptyStateView(
                    icon: .tasks,
                    title: emptyTitle,
                    message: filter == .open ? "交辦一件事給成員，任務就會出現在這裡。" : nil
                )
            }
            .refreshable { await store.refreshTasks() }
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(visibleTasks) { task in
                        TaskRowView(task: task) {
                            openTask = TaskRoute(id: task.id)
                        } onDecide: {
                            // Jump straight to the card blocking this task.
                            if let cardId = blockingCardId(for: task) {
                                openCard = CardRoute(id: cardId)
                            } else {
                                openTask = TaskRoute(id: task.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, OCMetrics.screenPadding)
                .padding(.bottom, 24)
            }
            .refreshable { await store.refreshTasks() }
        }
    }

    private var emptyTitle: String {
        switch filter {
        case .open: return "沒有未結束的任務"
        case .waitingOwner: return "沒有等你回覆的任務"
        case .closed: return "還沒有結束的任務"
        }
    }

    /// The waiting card bound to this task's gate step, if the detail is loaded;
    /// otherwise fall back to matching by task id on the inbox.
    private func blockingCardId(for task: TaskSummary) -> String? {
        if let detail = store.taskDetails[task.id],
           let step = detail.orderedSteps.first(where: { $0.status == .waitingOwner }),
           let cardId = step.replyCardId {
            return cardId
        }
        return store.waitingCards.first { $0.task?.id == task.id }?.id
    }
}
