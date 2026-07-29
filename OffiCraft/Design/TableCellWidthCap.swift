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
        let width = min(max(ideal, minWidth), maxWidth)
        let measured = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(width: width, height: measured.height)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        guard let subview = subviews.first else { return }
        // `bounds` is the column width Grid settled on, which is the widest
        // cell in this column — never narrower than what we measured, so the
        // height we reported stays an upper bound and rows cannot overlap.
        subview.place(at: bounds.origin,
                      proposal: ProposedViewSize(bounds.size))
    }
}
