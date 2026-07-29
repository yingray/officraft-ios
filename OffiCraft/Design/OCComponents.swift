import SwiftUI

// MARK: - Chips

/// Outlined status pill: `● 高`, `● 等我回覆`, `● review-pr`, `已過期`.
struct StatusChip: View {
    let text: String
    var tint: Color = OC.labelTertiary
    /// The leading `●`. Off for neutral labels like 已過期 / 產物 3.
    var showsDot: Bool = true
    var bordered: Bool = true
    var mono: Bool = false

    var body: some View {
        HStack(spacing: 5) {
            if showsDot {
                Text("●").font(.system(size: 8))
            }
            Text(text).font(mono ? .ocMono(11.5, weight: .bold) : .system(size: 11.5, weight: .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(
            Capsule().strokeBorder(bordered ? tint.opacity(0.42) : .clear, lineWidth: 1)
        )
    }
}

/// Solid low-alpha pill used for `AI 建議`, `審批`, `你選的`.
struct SolidChip: View {
    let text: String
    var tint: Color = OC.accent
    var background: Color?

    var body: some View {
        Text(text)
            .font(.ocMicro)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(background ?? tint.opacity(0.15)))
    }
}

/// `#T-4f2a` — monospaced task number with the task glyph.
struct TaskNumberChip: View {
    let taskNo: String
    var showsIcon: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            if showsIcon {
                Icon(.tasks, size: 12)
            }
            Text(taskNo.hasPrefix("#") ? taskNo : "#\(taskNo)")
                .font(.ocMono(12, weight: .bold))
        }
        .foregroundStyle(OC.taskNo)
        .padding(.horizontal, 9)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(OC.taskNo.opacity(0.12))
                .overlay(Capsule().strokeBorder(OC.taskNo.opacity(0.45), lineWidth: 1))
        )
    }
}

// MARK: - Avatar

/// Rounded-square member avatar with an initial, or the member's picture.
struct Avatar: View {
    let name: String
    var id: String = ""
    var imageURL: URL?
    var size: CGFloat = 34
    /// Small dot for presence, drawn by the caller when needed.
    var cornerRadius: CGFloat { size * 11 / 34 }

    private var palette: AvatarPalette {
        AvatarPalette.forKey(id.isEmpty ? name : id)
    }

    /// `Kyle` → `K`, `O-7` → `O-7` (short codenames stay whole).
    private var initials: String {
        if name.count <= 3, name.contains("-") { return name }
        return String(name.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(palette.background)
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsLabel
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                initialsLabel
            }
        }
        .frame(width: size, height: size)
    }

    private var initialsLabel: some View {
        Text(initials)
            .font(.system(size: size * (initials.count > 1 ? 0.33 : 0.41), weight: .bold))
            .foregroundStyle(palette.foreground)
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .padding(.horizontal, 2)
    }
}

/// Presence dot — 線上 / 喚醒中 / 離線.
struct PresenceDot: View {
    let presence: Presence
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(presence.tint)
            .frame(width: size, height: size)
    }
}

// MARK: - Progress

/// Thin progress track used on task cards and account usage meters.
struct OCProgressBar: View {
    /// 0…1
    let value: Double
    var tint: Color = OC.accent
    var height: CGFloat = 6
    /// Optional reference tick, 0…1. The usage meters put elapsed time here so
    /// "過熱" (spending faster than the clock) is visible, not just asserted.
    var marker: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(OC.label.opacity(0.08))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                if let marker {
                    Rectangle()
                        .fill(OC.label.opacity(0.55))
                        .frame(width: 1.5)
                        .offset(x: max(0, min(1, marker)) * geo.size.width - 0.75)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(
            Text(marker == nil
                 ? "\(Int((value * 100).rounded()))%"
                 : "已用 \(Int((value * 100).rounded()))%，時間進度 \(Int(((marker ?? 0) * 100).rounded()))%")
        )
    }
}

// MARK: - Segmented tabs

/// Two- or three-way inline switch: `待回覆 3` / `近期已處理 8`.
struct SegmentedTabs<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 8) {
            ForEach(items) { item in
                let isSelected = item.value == selection
                Button {
                    withAnimation(.snappy(duration: 0.18)) { selection = item.value }
                } label: {
                    Text(item.title)
                        .font(isSelected ? .system(size: 13.5, weight: .semibold) : .system(size: 13.5))
                        .foregroundStyle(isSelected ? OC.label : OC.labelTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? OC.surface2 : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Scrollable filter row: `未結束 12` / `等我回覆 2` / `已結束`.
struct FilterChipRow<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        let title: String
        var tint: Color?
        var id: Value { value }
    }

    let items: [Item]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let isSelected = item.value == selection
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { selection = item.value }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(
                                isSelected ? OC.label : (item.tint ?? OC.labelTertiary)
                            )
                            .fixedSize()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(isSelected ? OC.surface2 : .clear)
                                    .overlay(
                                        Capsule().strokeBorder(
                                            isSelected ? .clear : (item.tint ?? OC.hairline).opacity(0.4),
                                            lineWidth: 1
                                        )
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, OCMetrics.headerPadding)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Containers

/// Card surface used by 請示卡 / 任務卡.
struct OCCard<Content: View>: View {
    var borderTint: Color?
    var radius: CGFloat = OCMetrics.cardRadius
    var padding: EdgeInsets = EdgeInsets(top: 14, leading: 15, bottom: 13, trailing: 15)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(OC.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(borderTint ?? OC.hairline, lineWidth: 1)
                    )
            )
    }
}

/// iOS grouped-list section: an uppercase label, a rounded container of rows,
/// and an optional explanatory footnote.
struct GroupedSection<Content: View>: View {
    var header: String?
    var footer: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let header {
                Text(header).ocSectionLabel().padding(.leading, 14)
            }
            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: OCMetrics.groupRadius, style: .continuous)
                        .fill(OC.surface)
                )
                .clipShape(RoundedRectangle(cornerRadius: OCMetrics.groupRadius, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.ocCaption)
                    .foregroundStyle(OC.labelQuaternary)
                    .lineSpacing(2)
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
            }
        }
    }
}

/// One row inside a `GroupedSection`.
struct GroupedRow<Trailing: View>: View {
    let title: String
    var titleTint: Color = OC.label
    var isLast: Bool = false
    // `trailing` sits before `action` so an unlabelled trailing closure binds
    // to the view builder, and taps are always passed as `action:`.
    @ViewBuilder var trailing: Trailing
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action {
                Button(action: action) { rowBody }.buttonStyle(.plain)
            } else {
                rowBody
            }
        }
    }

    private var rowBody: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.ocBody)
                    .foregroundStyle(titleTint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(minHeight: OCMetrics.minTapTarget)
            .contentShape(Rectangle())

            if !isLast {
                Hairline(inset: 14)
            }
        }
    }
}

extension GroupedRow where Trailing == EmptyView {
    init(title: String,
         titleTint: Color = OC.label,
         isLast: Bool = false,
         action: (() -> Void)? = nil) {
        self.init(title: title, titleTint: titleTint, isLast: isLast,
                  trailing: { EmptyView() }, action: action)
    }
}

/// The `值 ›` trailing pair used throughout the settings list.
struct RowValue: View {
    let text: String
    var showsChevron: Bool = true
    var mono: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(mono ? .ocMono(14) : .ocCallout)
                .foregroundStyle(OC.labelTertiary)
                .lineLimit(1)
            if showsChevron {
                Icon(.chevronRight, size: 13).foregroundStyle(OC.labelQuaternary)
            }
        }
    }
}

// MARK: - Page header

/// Large-title page header with optional trailing controls.
struct PageHeader<Trailing: View>: View {
    let title: String
    var eyebrow: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.system(size: 12.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(OC.labelTertiary)
                }
                Text(title)
                    .font(.ocLargeTitle)
                    .foregroundStyle(OC.label)
            }
            Spacer(minLength: 8)
            trailing.padding(.bottom, 6)
        }
        .padding(.horizontal, OCMetrics.headerPadding)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, eyebrow: String? = nil) {
        self.init(title: title, eyebrow: eyebrow) { EmptyView() }
    }
}

/// Circular icon button in a page header (34pt, still inside a 44pt tap target).
struct HeaderIconButton: View {
    let icon: OCIcon
    var size: CGFloat = 17
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(icon, size: size)
                .foregroundStyle(OC.accent)
                .frame(width: 34, height: 34)
                .background(Circle().fill(OC.surface))
                .frame(width: OCMetrics.minTapTarget, height: OCMetrics.minTapTarget)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Badges

/// Red count badge on a tab item or a roster row.
struct CountBadge: View {
    let count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 19, minHeight: 19)
            .background(Capsule().fill(OC.badge))
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: OCIcon
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 12) {
            Icon(icon, size: 34).foregroundStyle(OC.labelQuaternary)
            Text(title)
                .font(.ocCalloutEmphasised)
                .foregroundStyle(OC.labelSecondary)
            if let message {
                Text(message)
                    .font(.ocFootnote)
                    .foregroundStyle(OC.labelTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .padding(.vertical, 48)
    }
}

// MARK: - Composer

/// Bottom message bar: attach, text field, send.
/// Enter inserts a newline on iPhone; send goes through the button (design doc
/// interaction rules). iPad additionally accepts ⌘↩.
struct Composer: View {
    @Binding var text: String
    var placeholder: String
    var accentSend: Bool = true
    var showsMarkdownToggle: Bool = false
    @Binding var markdownPreview: Bool
    /// Staged attachments. Empty binding means the composer has no `+`.
    @Binding var attachments: [PendingAttachment]
    var onPickPhotos: (() -> Void)?
    var onPickFiles: (() -> Void)?
    var onSend: () -> Void

    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                AttachmentTray(attachments: $attachments)
            }
            inputRow
        }
    }

    private var inputRow: some View {
        HStack(alignment: .bottom, spacing: 9) {
            if onPickPhotos != nil || onPickFiles != nil {
                Menu {
                    if let onPickPhotos {
                        Button("照片") { onPickPhotos() }
                    }
                    if let onPickFiles {
                        Button("檔案") { onPickFiles() }
                    }
                } label: {
                    Icon(.plus, size: 17)
                        .foregroundStyle(OC.labelSecondary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(OC.surface))
                }
                .accessibilityLabel("附加檔案")
            }

            HStack(spacing: 8) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(.ocCallout)
                    .foregroundStyle(OC.labelBody)
                    .lineLimit(1...5)
                    .focused($focused)
                    .submitLabel(.return)

                if showsMarkdownToggle {
                    Button {
                        markdownPreview.toggle()
                    } label: {
                        Text("MD 預覽")
                            .font(.system(size: 11.5))
                            .foregroundStyle(markdownPreview ? OC.accent : OC.labelTertiary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(OC.surface2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(OC.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(OC.hairline, lineWidth: 1)
                    )
            )

            Button(action: onSend) {
                Icon(.send, size: 16)
                    .foregroundStyle(canSend ? (accentSend ? OC.accent : .white) : OC.labelQuaternary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle().fill(
                            canSend
                                ? (accentSend ? OC.accentFill : OC.bubbleOwn)
                                : OC.surface
                        )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .keyboardShortcut(.return, modifiers: .command)
            .accessibilityLabel("送出")
        }
    }
}

extension Composer {
    /// Convenience for the screens with neither a markdown toggle nor
    /// attachments — the reply-card and task-message composers.
    init(text: Binding<String>,
         placeholder: String,
         accentSend: Bool = true,
         onSend: @escaping () -> Void) {
        self.init(
            text: text,
            placeholder: placeholder,
            accentSend: accentSend,
            showsMarkdownToggle: false,
            markdownPreview: .constant(false),
            attachments: .constant([]),
            onPickPhotos: nil,
            onPickFiles: nil,
            onSend: onSend
        )
    }

    /// Convenience for a composer with attachments but no markdown toggle —
    /// chat, where the owner writes a short reply rather than a document.
    init(text: Binding<String>,
         placeholder: String,
         accentSend: Bool = true,
         attachments: Binding<[PendingAttachment]>,
         onPickPhotos: (() -> Void)? = nil,
         onPickFiles: (() -> Void)? = nil,
         onSend: @escaping () -> Void) {
        self.init(
            text: text,
            placeholder: placeholder,
            accentSend: accentSend,
            showsMarkdownToggle: false,
            markdownPreview: .constant(false),
            attachments: attachments,
            onPickPhotos: onPickPhotos,
            onPickFiles: onPickFiles,
            onSend: onSend
        )
    }
}

// MARK: - Misc

/// Hairline divider that matches the grouped-list separator weight.
struct Hairline: View {
    var inset: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(OC.separator)
            .frame(height: 1 / max(displayScale, 1))
            .padding(.leading, inset)
    }
}

/// Scrim behind a bottom action stack, so content scrolls under it legibly.
struct BottomScrim: View {
    var body: some View {
        LinearGradient(
            colors: [OC.bg.opacity(0), OC.bg.opacity(0.92)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
