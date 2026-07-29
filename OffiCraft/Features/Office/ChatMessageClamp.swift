import CoreGraphics

/// When a chat message is too tall to sit in the transcript whole.
///
/// Height, not character count. What an agent sends is block markdown: a table
/// with eight rows and a fenced code block are short in characters and tall on
/// screen, and a wrapped paragraph is the other way round. Counting characters
/// would fold the wrong messages in both directions.
enum ChatMessageClamp {
    /// How much of an overlong message stays on screen — about a dozen lines of
    /// body text, less than half the transcript on a phone, so the reader still
    /// sees enough to decide whether to open it.
    static let collapsedHeight: CGFloat = 320

    /// A message only a little over the cap is left alone. Clipping four lines
    /// to save two is worse than just showing them, and it puts a 展開 row under
    /// a bubble that did not need one.
    static let slack: CGFloat = 88

    /// The height above which a message is folded by default.
    static var foldThreshold: CGFloat { collapsedHeight + slack }

    /// Whether a message of this rendered height should start folded.
    ///
    /// `naturalHeight` is 0 before the first layout pass has measured anything;
    /// nothing folds until a real height arrives, so a message never flashes
    /// collapsed on its way in.
    static func isOverlong(naturalHeight: CGFloat) -> Bool {
        naturalHeight > foldThreshold
    }

    /// The cap to apply, or `nil` for "no cap" — the shape SwiftUI's
    /// `frame(maxHeight:)` wants.
    static func cap(naturalHeight: CGFloat, isExpanded: Bool) -> CGFloat? {
        guard !isExpanded, isOverlong(naturalHeight: naturalHeight) else { return nil }
        return collapsedHeight
    }
}
