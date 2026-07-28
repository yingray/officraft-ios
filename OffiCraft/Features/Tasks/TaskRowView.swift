import SwiftUI

/// One task in the list. Progress-first: a glance answers "which step is it on,
/// and what is it stuck behind".
struct TaskRowView: View {
    let task: TaskSummary
    var onOpen: () -> Void
    var onDecide: (() -> Void)?

    @Environment(StudioStore.self) private var store

    /// The card outline carries the blocking state, so a scan of the list
    /// surfaces 等我回覆 and 等待外部 without reading a word.
    private var borderTint: Color {
        switch task.status {
        case .waitingOwner: return OC.waitingBorder
        case .waitingExternal: return OC.external.opacity(0.4)
        default: return OC.hairline
        }
    }

    var body: some View {
        OCCard(borderTint: borderTint) {
            metaRow
            Text(task.title)
                .font(.ocHeadline)
                .foregroundStyle(OC.label)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            executorRow

            if task.progressTotal > 0 {
                progressRow
            }

            switch task.status {
            case .waitingOwner:
                waitingOnYouBox
            case .waitingExternal:
                waitingExternalBox
            default:
                EmptyView()
            }

            if let deps = task.deps, !deps.isEmpty {
                ForEach(deps, id: \.self) { dependencyBox(for: $0) }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    // MARK: Rows

    private var metaRow: some View {
        HStack(spacing: 7) {
            TaskNumberChip(taskNo: task.taskNo)
            StatusChip(text: task.priority.label,
                       tint: task.priority.tint,
                       bordered: task.priority.isBordered)
            StatusChip(text: task.status.label, tint: task.status.tint)
            if task.isReassigning {
                StatusChip(text: "轉派中", tint: OC.frozen, showsDot: false)
            }
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 14).foregroundStyle(OC.labelQuaternary)
        }
    }

    private var executorRow: some View {
        HStack(spacing: 8) {
            if !task.typeKey.isEmpty {
                StatusChip(text: task.typeKey, tint: OC.taskType)
            }
            Text(executorLabel)
                .font(.ocFootnote)
                .foregroundStyle(OC.labelTertiary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var executorLabel: String {
        var parts = [store.displayName(for: task.executorId)]
        let role = store.roleName(for: task.executorId)
        if !role.isEmpty { parts.append(role) }
        return parts.joined(separator: " · ")
    }

    private var progressRow: some View {
        HStack(spacing: 11) {
            OCProgressBar(value: task.progress, tint: task.status.tint)
            Text("\(task.progressLabel) · \(OCFormat.elapsed(since: task.createdAt))")
                .font(.ocFootnoteSmall)
                .foregroundStyle(OC.labelTertiary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    // MARK: Blocking boxes

    private var waitingOnYouBox: some View {
        Button {
            (onDecide ?? onOpen)()
        } label: {
            HStack(spacing: 9) {
                Icon(.inbox, size: 13)
                Text("卡在你：\(task.waitingReason ?? "需要你拍板")")
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("去決定")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(OC.waiting)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: OCMetrics.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(OC.waitingWash)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(OC.waitingBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var waitingExternalBox: some View {
        HStack(spacing: 9) {
            Icon(.clock, size: 12)
            Text(task.waitingReason ?? "等待外部回覆")
                .font(.ocFootnote)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(OC.externalText)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(OC.externalWash)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(OC.external.opacity(0.35), lineWidth: 1)
                )
        )
    }

    /// A blocking dependency: which task, in what state, and what it is for.
    @ViewBuilder
    private func dependencyBox(for dependencyId: String) -> some View {
        let dependency = store.tasks.first { $0.id == dependencyId }
        HStack(spacing: 9) {
            StatusChip(text: dependency?.status.label ?? "尚未執行",
                       tint: OC.labelSecondary)
            Text(dependency?.taskNo ?? dependencyId)
                .font(.ocMono(12))
                .foregroundStyle(OC.frozenMono)
            Text("等：\(dependency?.title ?? "上游任務")")
                .font(.ocFootnoteSmall)
                .foregroundStyle(OC.frozenText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(OC.frozen.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(OC.frozen.opacity(0.4), lineWidth: 1)
                )
        )
    }
}
