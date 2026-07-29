import SwiftUI

/// The one-line stand-in for a folded run, and the block it opens into.
///
/// Both lanes get the same shape — a 44pt row with a chevron, a label and a
/// count — so the owner learns one affordance, not two. They differ only in
/// tint: inter-agent borrows the task blue, system borrows the 外包 purple the
/// rest of the app already uses for "not one of us".
struct ChatFoldRow: View {
    let lane: ChatLane
    let count: Int
    let isExpanded: Bool
    /// Who is talking to whom in this run — "Kyle ⇄ Sasha". Empty for system.
    let participants: String
    var action: () -> Void

    private var tint: Color {
        lane == .system ? OC.externalText : OC.taskNo
    }

    private var label: String {
        switch (lane, isExpanded) {
        case (.system, false): return "\(count) 則換手交接 · 展開"
        case (.system, true): return "收合換手交接"
        case (_, false): return "\(count) 則成員間對話 · 展開"
        case (_, true): return "收合成員間對話"
        }
    }

    private var chipText: String {
        if isExpanded {
            return lane == .system ? "系統 · \(count) 則" : "\(count) 則"
        }
        return lane == .system ? "系統" : participants
    }

    /// Collapsed inter-agent rows stay neutral so they read as background; once
    /// opened, or once it is a system notice, the lane's colour comes forward.
    private var fill: Color {
        if lane == .system { return OC.externalWash }
        return isExpanded ? OC.taskNo.opacity(0.10) : OC.label.opacity(0.035)
    }

    private var border: Color {
        if lane == .system { return OC.external.opacity(isExpanded ? 0.32 : 0.28) }
        return isExpanded ? OC.taskNo.opacity(0.30) : OC.hairline
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Icon(isExpanded ? .chevronDown : .chevronRight, size: 14)
                    .foregroundStyle(isExpanded || lane == .system
                                     ? tint.opacity(isExpanded ? 1 : 0.6)
                                     : OC.labelQuaternary)
                Text(label)
                    .font(.system(size: 13.5, weight: isExpanded ? .semibold : .regular))
                    .foregroundStyle(foldLabelTint)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !chipText.isEmpty {
                    Text(chipText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.16)))
                        .layoutPriority(-1)
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: OCMetrics.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(border, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "\(label)，\(count) 則" : label)
    }

    private var foldLabelTint: Color {
        if isExpanded { return tint }
        return lane == .system ? tint : OC.labelSecondary
    }
}

// MARK: - Expanded rows

/// One message inside an opened fold.
///
/// Every row states "發送者 → 收件者" above the bubble. In a folded lane the
/// owner is on neither end, so without the header there is nothing on screen to
/// say who is talking — the side a bubble sits on cannot carry that.
struct ChatFoldedMessageRow: View {
    let lane: ChatLane
    let header: String
    let message: ChatMessage
    var onOpenAttachment: (Attachment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(header)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(lane == .system ? OC.externalText.opacity(0.85) : OC.labelTertiary)
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 8) {
                MarkdownView(message.body, scale: .message)

                if let attachments = message.attachments, !attachments.isEmpty {
                    AttachmentStrip(attachments: attachments,
                                    compact: true,
                                    onOpen: onOpenAttachment)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(lane == .system ? OC.externalWash : OC.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(lane == .system ? OC.external.opacity(0.22) : .clear,
                                          lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The indented rule that ties an opened fold's rows back to its header.
struct ChatFoldedBody<Content: View>: View {
    let lane: ChatLane
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Rectangle()
                .fill(lane == .system ? OC.external.opacity(0.30) : OC.taskNo.opacity(0.28))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 9) {
                content
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
