import SwiftUI

/// Clamps a table cell's width and reports the height it will actually draw at.
///
/// This exists because of a specific `Grid` trap. `Grid` sizes a row from each
/// cell's *ideal* size, and a plain `.frame(maxWidth:)` caps the ideal width
/// while still reporting the single-line ideal *height*. The text then wraps at
/// render time without the row having grown for it, and the extra lines spill
/// into the row below. Measuring the child a second time — at the clamped
/// width — makes the reported height match what is drawn.
///
/// Without that measurement the only safe cell is a one-line cell, which is why
/// this table used to truncate. Apple's guidance is the opposite: "avoid
/// truncating text in scrollable regions unless people can open a separate view
/// to read the rest of the content."
///
/// One precondition, and it is load-bearing: the grid must be free to take its
/// natural size. Offer `Grid` less than it asks for and it compresses — narrower
/// columns than were measured, or height taken out of the most flexible row —
/// and the height reported here stops matching what is drawn, so content spills
/// out of its row and is clipped. It surfaces as the last row cut off when the
/// squeeze is horizontal, and as the header text escaping its tint when it is
/// vertical. `TableBlock` pins the grid with `fixedSize()` for exactly this
/// reason; remove that and this type is quietly wrong again.
struct TableCellWidthCap: Layout {
    /// Narrow columns still need to hold a word. 96pt is roughly the floor at
    /// which a Chinese or English label stays readable at 12.5pt.
    var minWidth: CGFloat = 96
    /// 260pt ≈ two thirds of a 393pt screen: wide enough for a sentence, narrow
    /// enough that two columns still fit a phone.
    var maxWidth: CGFloat = 260

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        // The ideal, not the proposal: inside a horizontal ScrollView the
        // proposed width is unbounded, so asking for it would defeat the cap.
        let ideal = subview.sizeThatFits(.unspecified).width
        var width = min(max(ideal, minWidth), maxWidth)
        // Once Grid has settled the column it proposes that width back. Taking
        // it when it is finite and wider does two things: a short header cell
        // fills its column, so the tint has no gap, and the height below is
        // measured at the width the cell is actually drawn at rather than at a
        // narrower guess — measuring narrow is what left the last row a line
        // short of what it rendered.
        if let proposed = proposal.width, proposed.isFinite, proposed > width {
            width = proposed
        }
        let measured = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: measured.height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        guard let subview = subviews.first else { return }
        // `bounds` is the column width Grid settled on. That is only the widest
        // cell in the column while Grid is free to take its natural width — squeeze
        // the grid and it hands back less, the text wraps an extra line and the row
        // overflows. TableBlock pins the grid with `fixedSize` so that cannot
        // happen; without it the height reported above stops being an upper bound.
        subview.place(at: bounds.origin,
                      proposal: ProposedViewSize(bounds.size))
    }
}
