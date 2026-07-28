import SwiftUI
import WidgetKit
import ActivityKit

/// 任務進度 · Live Activity — Lock Screen card and Dynamic Island.
struct TaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color(hex: 0x1C1C1E).opacity(0.9))
                .activitySystemActionForegroundColor(Color(hex: 0x6FD6B0))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.taskNo)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    } icon: {
                        Image(systemName: "checkmark.square")
                    }
                    .foregroundStyle(Color(hex: 0x8BA3E6))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.progressLabel)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white.opacity(0.7))
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressTrack(state: context.state)
                }
            } compactLeading: {
                Image(systemName: context.state.waitingCards > 0 ? "tray.full" : "checkmark.square")
                    .foregroundStyle(tint(for: context.state))
            } compactTrailing: {
                if context.state.waitingCards > 0 {
                    Text("\(context.state.waitingCards)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xE0B341))
                } else {
                    Text("\(context.state.progressDone)/\(context.state.progressTotal)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(hex: 0x6FD6B0))
                        .monospacedDigit()
                }
            } minimal: {
                Image(systemName: context.state.waitingCards > 0 ? "tray.full" : "checkmark.square")
                    .foregroundStyle(tint(for: context.state))
            }
            .keylineTint(tint(for: context.state))
        }
    }

    private func tint(for state: TaskActivityAttributes.ContentState) -> Color {
        // 等我回覆 is the only interrupting colour, per the design system.
        state.isWaitingOnOwner || state.waitingCards > 0
            ? Color(hex: 0xE0B341)
            : Color(hex: 0x6FD6B0)
    }
}

// MARK: - Lock Screen

private struct LockScreenView: View {
    let context: ActivityViewContext<TaskActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.square")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x8BA3E6))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(hex: 0x1C1C1E))
                    )
                Text("任務進度 · Live Activity")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 4)
                Text("#\(context.attributes.taskNo)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color(hex: 0x8BA3E6))
            }

            Text(context.attributes.title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            if let step = context.state.currentStep, !step.isEmpty {
                Text(step)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }

            ProgressTrack(state: context.state)
        }
        .padding(15)
    }
}

// MARK: - Shared progress track

private struct ProgressTrack: View {
    let state: TaskActivityAttributes.ContentState

    private var tint: Color {
        state.isWaitingOnOwner ? Color(hex: 0xE0B341) : Color(hex: 0x6FD6B0)
    }

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.16))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, min(1, state.fraction)) * geo.size.width)
                }
            }
            .frame(height: 6)

            Text(state.progressLabel)
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize()
        }
    }
}

// MARK: - Colour helper

/// The widget target does not link the app's design tokens, so it carries the
/// handful of hex values it needs.
private extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
