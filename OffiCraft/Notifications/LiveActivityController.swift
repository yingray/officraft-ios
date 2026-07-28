import Foundation
import ActivityKit

/// Starts, updates and ends the task Live Activity.
///
/// One activity at a time: the Lock Screen is for the task you asked to watch,
/// not a feed. Starting a second one replaces the first.
@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<TaskActivityAttributes>?

    var trackedTaskId: String? { activity?.attributes.taskId }

    var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func isTracking(_ taskId: String) -> Bool {
        trackedTaskId == taskId && activity?.activityState == .active
    }

    /// Begin tracking a task on the Lock Screen and in the Dynamic Island.
    func start(task: TaskDetail, executorName: String, waitingCards: Int) {
        guard isSupported else { return }
        Task { await end() }

        let attributes = TaskActivityAttributes(
            taskId: task.id,
            taskNo: task.taskNo,
            title: task.title,
            executorName: executorName
        )
        let state = contentState(for: task, waitingCards: waitingCards)

        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func update(task: TaskDetail, waitingCards: Int) async {
        guard let activity, activity.attributes.taskId == task.id else { return }
        await activity.update(
            ActivityContent(state: contentState(for: task, waitingCards: waitingCards),
                            staleDate: nil)
        )
    }

    func end() async {
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }

    private func contentState(for task: TaskDetail,
                              waitingCards: Int) -> TaskActivityAttributes.ContentState {
        // The step worth naming is the one currently blocking or running.
        let step = task.orderedSteps.first {
            $0.status == .waitingOwner || $0.status == .waitingExternal || $0.status == .inProgress
        }
        return TaskActivityAttributes.ContentState(
            progressDone: task.progressDone,
            progressTotal: task.progressTotal,
            statusLabel: task.status.label,
            isWaitingOnOwner: task.status == .waitingOwner,
            currentStep: step.map { "\($0.status.label)：\($0.name)" },
            waitingCards: waitingCards
        )
    }
}
