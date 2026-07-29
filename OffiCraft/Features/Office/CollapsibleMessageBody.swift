import SwiftUI

/// A message body that starts clipped when it is very long, with 展開 to open it.
///
/// The measurement is the point. The content keeps its natural height — that is
/// what `fixedSize` is doing here, and why the `GeometryReader` sits in the
/// background *before* the cap is applied — and the cap only clips what is
/// already laid out. Because the child ignores the height the cap proposes, the
/// measured value never depends on the cap, so folding cannot feed back into
/// the measurement and start a layout loop.
///
/// The cut edge is faded with a mask rather than a gradient painted over it: a
/// mask fades the content itself, so this works on any bubble fill and no
/// caller has to hand its background colour in.
struct CollapsibleMessageBody<Content: View>: View {
    /// Whether the owner has opened this one. Held by the transcript, keyed by
    /// message id, so an SSE refetch that swaps the array does not close it.
    let isExpanded: Bool
    var alignment: HorizontalAlignment = .leading
    /// The 展開/收合 row's colour. Own bubbles are dark blue, so the grey the
    /// rest of the transcript uses would sink into them.
    var tint: Color = OC.labelTertiary
    var onToggle: () -> Void
    @ViewBuilder var content: Content

    @State private var naturalHeight: CGFloat = 0

    private var isOverlong: Bool {
        ChatMessageClamp.isOverlong(naturalHeight: naturalHeight)
    }

    /// Non-nil only while this message is actually folded.
    private var cap: CGFloat? {
        ChatMessageClamp.cap(naturalHeight: naturalHeight, isExpanded: isExpanded)
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            // Rounded before storing: a sub-pixel re-measure
                            // would otherwise publish new state on every
                            // layout pass. `initial` catches the first one —
                            // markdown settles its height after the first
                            // pass, so the height that matters often arrives
                            // as a change, not on appear.
                            .onChange(of: proxy.size.height, initial: true) { _, height in
                                let rounded = height.rounded()
                                if abs(rounded - naturalHeight) >= 1 {
                                    naturalHeight = rounded
                                }
                            }
                    }
                )
                .frame(maxHeight: cap, alignment: .top)
                .clipped()
                .mask { clipMask }
                // Tapping the body opens it, and only opens it. Once it is
                // open the text is text again — selecting a line or following
                // a link must not fold it back up.
                .contentShape(Rectangle())
                .onTapGesture { if cap != nil { toggle() } }

            if isOverlong { toggleRow }
        }
    }

    private func toggle() {
        withAnimation(.snappy(duration: 0.22)) { onToggle() }
    }

    /// Fades the last stretch of a folded message so the cut reads as "there is
    /// more", not as a message that stops mid-sentence.
    @ViewBuilder
    private var clipMask: some View {
        if let cap {
            let fadeStart = max(0, (cap - Self.fadeHeight) / cap)
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: fadeStart),
                    .init(color: .black.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Rectangle()
        }
    }

    private static let fadeHeight: CGFloat = 46

    private var toggleRow: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                // The two glyphs the run fold already uses, so the affordance
                // is learned once: pointing right is closed, down is open.
                Icon(isExpanded ? .chevronDown : .chevronRight, size: 11)
                Text(isExpanded ? "收合" : "展開全文")
                    .font(.ocCaption)
            }
            .foregroundStyle(tint)
            // No maxWidth here on purpose: the enclosing VStack's alignment
            // already places the row, and stretching it would widen an own
            // bubble that should stay as narrow as its text.
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "收合這則訊息" : "展開這則訊息全文")
    }
}
