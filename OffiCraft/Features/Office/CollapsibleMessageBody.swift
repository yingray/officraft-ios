import SwiftUI

/// A message body that stays clipped when very long, with a door to its viewer.
///
/// Two heights, in order: a rough estimate from the text decides the first
/// frame, and the measured height takes over once the row has been laid out.
///
/// The measurement is what makes the fade honest. The content keeps its natural
/// height — that is what `fixedSize` is doing here, and why the `GeometryReader`
/// sits in the background *before* the cap is applied — and the cap only clips
/// what is already laid out. Because the child ignores the height the cap
/// proposes, the measured value never depends on the cap, so folding cannot
/// feed back into the measurement and start a layout loop.
///
/// The cut edge is faded with a mask rather than a gradient painted over it: a
/// mask fades the content itself, so this works on any bubble fill and no
/// caller has to hand its background colour in.
struct CollapsibleMessageBody<Content: View>: View {
    /// The raw text behind `content`, used only to guess a height for the very
    /// first frame. The transcript is a `LazyVStack` — a row's state is thrown
    /// away when it scrolls off and rebuilt when it comes back — so waiting for
    /// a measurement would draw the message out in full, every time, before
    /// snapping shut.
    let source: String
    var alignment: HorizontalAlignment = .leading
    /// The 展開全文 row's colour. Own bubbles are dark blue, so the grey the
    /// rest of the transcript uses would sink into them.
    var tint: Color = OC.labelTertiary
    let onOpenFullText: () -> Void
    @ViewBuilder var content: Content

    /// Nil until the row has been laid out once; the estimate stands in for it
    /// until then, and the real height replaces it for good afterwards.
    @State private var measuredHeight: CGFloat?

    private var naturalHeight: CGFloat {
        measuredHeight ?? ChatMessageClamp.estimatedHeight(of: source)
    }

    private var isOverlong: Bool {
        ChatMessageClamp.isOverlong(naturalHeight: naturalHeight)
    }

    private var cap: CGFloat? {
        ChatMessageClamp.cap(naturalHeight: naturalHeight)
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
                                if measuredHeight.map({ abs(rounded - $0) >= 1 }) ?? true {
                                    measuredHeight = rounded
                                }
                            }
                    }
                )
                .frame(maxHeight: cap, alignment: .top)
                .clipped()
                .mask { clipMask }
                // The overlay covers the whole clipped body, not just the
                // fade, so anywhere on a folded message opens the viewer. It
                // does swallow taps meant for links and the code block's 複製
                // button — that is the same trade the folded state always made,
                // and the viewer is where those are reachable.
                // Hidden from VoiceOver: an element laid over the text would
                // hide the text. The labelled row below is the accessible way
                // in.
                .overlay {
                    if cap != nil {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenFullText() }
                            .accessibilityHidden(true)
                    }
                }

            if isOverlong { openRow }
        }
    }

    /// Fades the last stretch of a folded message so the cut reads as "there is
    /// more", not as a message that stops mid-sentence.
    @ViewBuilder
    private var clipMask: some View {
        if cap != nil {
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: ChatMessageClamp.fadeStart),
                    .init(color: .black.opacity(0), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Rectangle()
        }
    }

    private var openRow: some View {
        Button(action: onOpenFullText) {
            HStack(spacing: 5) {
                Icon(.chevronRight, size: 11)
                Text("展開全文")
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
        .accessibilityLabel("以全螢幕展開這則訊息全文")
    }
}
