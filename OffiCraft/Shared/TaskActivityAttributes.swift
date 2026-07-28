import Foundation
import ActivityKit

/// Live Activity payload for a running task.
///
/// Compiled into both the app and the widget extension, so the two agree on
/// the shape without a shared framework.
struct TaskActivityAttributes: ActivityAttributes {

    /// The parts that change while the task runs.
    struct ContentState: Codable, Hashable {
        var progressDone: Int
        var progressTotal: Int
        /// One of the eight task states, already localised.
        var statusLabel: String
        /// Drives the colour: only 等我回覆 is allowed to look urgent.
        var isWaitingOnOwner: Bool
        /// What the current step is, when there is one worth naming.
        var currentStep: String?
        /// Reply cards waiting overall — the Dynamic Island's compact readout.
        var waitingCards: Int

        var fraction: Double {
            progressTotal > 0 ? Double(progressDone) / Double(progressTotal) : 0
        }

        var progressLabel: String { "步驟 \(progressDone)/\(progressTotal)" }
    }

    /// Fixed for the lifetime of the activity.
    var taskId: String
    var taskNo: String
    var title: String
    var executorName: String
}
