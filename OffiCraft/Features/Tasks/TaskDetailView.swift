import SwiftUI
import UIKit

/// 任務 · 詳情 — the step timeline with definitions of done and, for gate
/// steps, the reply card embedded so a decision never leaves the task.
struct TaskDetailView: View {
    let taskId: String

    @Environment(StudioStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var detail: TaskDetail?
    @State private var message = ""
    @State private var openCard: CardRoute?
    @State private var preview: PreviewTarget?
    @State private var didSendMessage = false
    @State private var isTracking = false

    var body: some View {
        VStack(spacing: 0) {
            navBar
            if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(detail.title)
                            .font(.ocTitle3Compact)
                            .foregroundStyle(OC.label)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)

                        chipRow(detail)
                        progressCard(detail)

                        if let description = detail.description, !description.isEmpty {
                            MarkdownView(description, scale: .message)
                        }

                        timeline(detail)

                        if let artifacts = detail.artifacts, !artifacts.isEmpty {
                            artifactSection(artifacts)
                        }

                        if let note = detail.handoverNote, !note.isEmpty {
                            handoverBox(note, by: detail.handoverNoteBy)
                        }
                    }
                    .padding(.horizontal, OCMetrics.headerPadding)
                    .padding(.top, 14)
                    .padding(.bottom, 20)
                }

                composer(detail)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(OC.bg)
        .navigationBarHidden(true)
        .navigationDestination(item: $openCard) { route in
            AskDetailView(cardId: route.id)
        }
        .attachmentPreview($preview,
                           author: detail.map { store.displayName(for: $0.executorId) } ?? "",
                           taskNo: detail?.taskNo)
        .task {
            detail = await store.loadTaskDetail(taskId)
            isTracking = LiveActivityController.shared.isTracking(taskId)
        }
        .onChange(of: store.taskDetails[taskId]) {
            // Keep a running Live Activity in step with the task it tracks.
            guard isTracking, let detail = store.taskDetails[taskId] else { return }
            Task {
                await LiveActivityController.shared.update(
                    task: detail,
                    waitingCards: store.waitingCardCount
                )
            }
        }
    }

    /// 任務進度走 Live Activity — start or stop watching this task on the
    /// Lock Screen and in the Dynamic Island.
    private func toggleLiveActivity(_ detail: TaskDetail) {
        if isTracking {
            Task { await LiveActivityController.shared.end() }
            isTracking = false
        } else {
            LiveActivityController.shared.start(
                task: detail,
                executorName: store.displayName(for: detail.executorId),
                waitingCards: store.waitingCardCount
            )
            isTracking = true
        }
    }

    // MARK: Chrome

    private var navBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 3) {
                        Icon(.chevronLeft, size: 15)
                        Text("任務").font(.ocBody)
                    }
                    .foregroundStyle(OC.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                Text("#\(detail?.taskNo ?? "")")
                    .font(.ocMono(13, weight: .bold))
                    .foregroundStyle(OC.taskNo)

                Spacer()

                Menu {
                    if let detail {
                        if LiveActivityController.shared.isSupported {
                            Button(isTracking ? "停止鎖定畫面追蹤" : "在鎖定畫面追蹤") {
                                toggleLiveActivity(detail)
                            }
                        }
                        Menu("優先權") {
                            ForEach([TaskPriority.high, .mid, .low, .frozen], id: \.self) { priority in
                                Button(priority.label) {
                                    Task {
                                        await store.setPriority(taskId: detail.id, priority: priority)
                                        self.detail = await store.loadTaskDetail(taskId)
                                    }
                                }
                            }
                        }
                        Button("複製任務編號") {
                            UIPasteboard.general.string = detail.taskNo
                        }
                    }
                } label: {
                    Icon(.ellipsis, size: 15)
                        .foregroundStyle(OC.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, OCMetrics.screenPadding)
            Hairline()
        }
    }

    // MARK: Header blocks

    private func chipRow(_ detail: TaskDetail) -> some View {
        HStack(spacing: 7) {
            StatusChip(text: detail.status.label, tint: detail.status.tint)
            StatusChip(text: detail.priority.label,
                       tint: detail.priority.tint,
                       bordered: detail.priority.isBordered)
            if let artifacts = detail.artifacts, !artifacts.isEmpty {
                StatusChip(text: "產物 \(artifacts.count)",
                           tint: OC.dyn(light: 0xA85C7E, dark: 0xCF94B0),
                           showsDot: false)
            }
            Spacer(minLength: 0)
        }
    }

    private func progressCard(_ detail: TaskDetail) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                OCProgressBar(value: detail.progress, tint: detail.status.tint)
                Text("\(detail.progressDone) / \(detail.progressTotal)")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(OC.labelBody)
                    .monospacedDigit()
            }
            HStack {
                Text(OCFormat.elapsed(since: detail.createdAt))
                    .font(.ocFootnoteSmall)
                    .foregroundStyle(OC.labelTertiary)
                Spacer()
                HStack(spacing: 5) {
                    Text("負責人 \(store.displayName(for: detail.executorId))")
                        .font(.ocFootnoteSmall)
                        .foregroundStyle(OC.labelTertiary)
                    Icon(.swap, size: 14).foregroundStyle(OC.labelTertiary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: OCMetrics.groupRadius, style: .continuous)
                .fill(OC.surface)
        )
    }

    // MARK: Timeline

    private func timeline(_ detail: TaskDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("工作流程 WORKFLOW").ocSectionLabel()

            let steps = detail.orderedSteps
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    TimelineNode(tint: step.status.nodeTint, isLast: index == steps.count - 1)
                    StepCard(step: step) { cardId in
                        openCard = CardRoute(id: cardId)
                    } onAnswer: { cardId, optionIdx in
                        Task { await answer(cardId: cardId, optionIdx: optionIdx) }
                    } onOpenAttachment: { attachment, siblings in
                        preview = previewTarget(for: attachment, in: siblings)
                    }
                }
            }
        }
    }

    private func answer(cardId: String, optionIdx: Int) async {
        guard let card = await store.loadCardDetail(cardId) else { return }
        await store.answer(card: card, optionIdx: optionIdx, text: nil)
        detail = await store.loadTaskDetail(taskId)
    }

    // MARK: Artifacts

    private func artifactSection(_ artifacts: [TaskArtifact]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("產物 ARTIFACTS").ocSectionLabel()
            AttachmentStrip(attachments: artifacts.map(\.asAttachment)) { attachment in
                preview = previewTarget(for: attachment, in: artifacts.map(\.asAttachment))
            }
        }
    }

    private func handoverBox(_ note: String, by author: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("換手筆記 HANDOVER").ocSectionLabel()
            VStack(alignment: .leading, spacing: 6) {
                if let author, !author.isEmpty {
                    Text(store.displayName(for: author))
                        .font(.ocFootnoteSmall)
                        .foregroundStyle(OC.labelTertiary)
                }
                MarkdownView(note, scale: .message)
            }
            .padding(13)
            .background(
                RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                    .fill(OC.surface)
            )
        }
    }

    // MARK: Composer

    private func composer(_ detail: TaskDetail) -> some View {
        VStack(spacing: 8) {
            if didSendMessage {
                Text("已送出給 \(store.displayName(for: detail.executorId))")
                    .font(.ocFootnoteSmall)
                    .foregroundStyle(OC.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Composer(
                text: $message,
                placeholder: "傳訊息給 \(store.displayName(for: detail.executorId))…",
                accentSend: false
            ) {
                let body = message
                message = ""
                Task {
                    await store.sendTaskMessage(taskId: detail.id, body: body)
                    withAnimation { didSendMessage = true }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { didSendMessage = false }
                }
            }
        }
        .padding(.horizontal, OCMetrics.headerPadding)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(BottomScrim().allowsHitTesting(false))
    }
}

// MARK: - Timeline node

/// The dot-and-rail on the left of a step.
private struct TimelineNode: View {
    let tint: Color
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 14)
            Circle().fill(tint).frame(width: 10, height: 10)
            if !isLast {
                Rectangle()
                    .fill(OC.label.opacity(0.09))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 10)
    }
}

// MARK: - Step card

/// One step: name, elapsed, status, definition of done — and, when it is a
/// gate, the reply card inline so the decision happens here.
private struct StepCard: View {
    let step: TaskStep
    var onOpenCard: (String) -> Void
    var onAnswer: (String, Int) -> Void
    var onOpenAttachment: (Attachment, [Attachment]) -> Void

    @Environment(StudioStore.self) private var store
    @State private var card: ReplyCard?

    private var isGateWaiting: Bool {
        step.status == .waitingOwner && step.replyCardId != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow

            if let dod = step.dod, !dod.isEmpty {
                (
                    Text("完成準則：").font(.system(size: 12.5, weight: .bold))
                        .foregroundColor(OC.labelSecondary)
                    + Text(dod).font(.ocFootnoteSmall)
                        .foregroundColor(OC.labelTertiary)
                )
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            }

            if step.status == .waitingExternal, let reason = step.waitingReason, !reason.isEmpty {
                HStack(spacing: 8) {
                    Icon(.clock, size: 12)
                    Text(reason).font(.ocFootnoteSmall)
                }
                .foregroundStyle(OC.externalText)
            }

            if isGateWaiting, let card {
                embeddedCard(card)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                .fill(isGateWaiting ? OC.waitingWash : OC.label.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: OCMetrics.optionRadius, style: .continuous)
                        .strokeBorder(isGateWaiting ? OC.waitingBorder : OC.hairline, lineWidth: 1)
                )
        )
        .opacity(step.status == .pending || step.status == .superseded ? 0.85 : 1)
        .task(id: step.replyCardId) {
            guard isGateWaiting, let cardId = step.replyCardId else { return }
            card = await store.loadCardDetail(cardId)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(step.name)
                .font(.ocOption)
                .foregroundStyle(OC.labelBody)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let elapsed = elapsedLabel {
                HStack(spacing: 4) {
                    Icon(.clock, size: 11)
                    Text(elapsed).font(.ocCaptionSmall)
                }
                .foregroundStyle(OC.labelQuaternary)
            }

            if step.isGate {
                SolidChip(text: "審批", tint: OC.waiting)
            }
            StatusChip(text: step.status.label, tint: step.status.tint,
                       showsDot: false,
                       bordered: step.status != .pending)
        }
    }

    private var elapsedLabel: String? {
        guard let started = step.startedTs else { return nil }
        let end = step.finishedTs ?? Date().timeIntervalSince1970
        guard end > started else { return nil }
        return OCFormat.duration(end - started)
    }

    /// The reply card, rendered inline so the gate can be cleared without
    /// leaving the task.
    private func embeddedCard(_ card: ReplyCard) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("請示卡")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(OC.waiting)
                Spacer()
                Button {
                    onOpenCard(card.id)
                } label: {
                    HStack(spacing: 3) {
                        Text("在請示頁開啟").font(.ocCaption)
                        Icon(.chevronRight, size: 10)
                    }
                    .foregroundStyle(OC.labelTertiary)
                    .frame(minHeight: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Text(MarkdownParser.inline(card.summary))
                .font(.ocSubhead.weight(.semibold))
                .foregroundStyle(OC.label)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            // The card's own attachments — often the very thing the decision
            // is made from, so they must be reachable without leaving the task.
            if let attachments = card.attachments, !attachments.isEmpty {
                AttachmentStrip(attachments: attachments, compact: true) { attachment in
                    onOpenAttachment(attachment, attachments)
                }
            }

            ForEach(Array((card.options ?? []).enumerated()), id: \.offset) { index, option in
                ReplyOptionRow(index: index, text: option,
                               isRecommended: index == 0, isCompact: true) {
                    onAnswer(card.id, index)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(OC.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(OC.waitingBorder, lineWidth: 1)
                )
        )
    }
}
