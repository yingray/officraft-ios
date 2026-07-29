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

    /// How much of the visible stretch is faded out at the cut.
    static let fadeHeight: CGFloat = 46

    /// Where the fade starts, as a fraction of the collapsed height — the shape
    /// a `LinearGradient` stop wants.
    static var fadeStart: CGFloat {
        max(0, (collapsedHeight - fadeHeight) / collapsedHeight)
    }

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

    // MARK: Seeding the first frame

    /// A rough height for a message body, from its text alone.
    ///
    /// This is a SEED, not a measurement — the real height replaces it as soon
    /// as the row has been laid out once. It exists because the transcript is a
    /// `LazyVStack`: a row's state is thrown away when it scrolls out of view
    /// and rebuilt when it comes back, so a fold decision that waits for a
    /// measurement would render the whole message once, every time, before
    /// snapping shut. Starting from an estimate means the common case is
    /// already right on the first frame.
    ///
    /// Deliberately crude. It reads the raw text, not the parsed markdown: it
    /// only has to tell "long" from "short", and being wrong costs one
    /// correction after the first layout pass.
    static func estimatedHeight(of body: String) -> CGFloat {
        // An attachment-only message has no body and draws nothing.
        guard !body.isEmpty else { return 0 }
        var lines: CGFloat = 0
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                // A blank line is a block break, which costs the stack's
                // spacing rather than a whole line.
                lines += 0.5
                continue
            }
            let units = line.reduce(CGFloat(0)) { $0 + widthUnits(of: $1) }
            lines += max(1, (units / unitsPerLine).rounded(.up))
        }
        return lines * lineHeight
    }

    /// One body line at the chat scale, its line spacing included.
    private static let lineHeight: CGFloat = 22

    /// Roughly how many half-width characters fit across a bubble on a phone.
    /// A wider screen folds slightly less than it could, which is the harmless
    /// direction to be wrong in.
    private static let unitsPerLine: CGFloat = 42

    /// CJK, kana and full-width punctuation take about two half-width slots.
    /// Every message in this app is a mix of Chinese and code, so counting
    /// characters without this is off by a factor of two.
    private static func widthUnits(of character: Character) -> CGFloat {
        guard let scalar = character.unicodeScalars.first else { return 1 }
        switch scalar.value {
        case 0x1100...0x115F,   // Hangul Jamo
             0x2E80...0x303E,   // CJK radicals, kana punctuation
             0x3041...0x33FF,   // kana, CJK compatibility
             0x3400...0x4DBF,   // CJK ext A
             0x4E00...0x9FFF,   // CJK unified
             0xA000...0xA4CF,   // Yi
             0xAC00...0xD7A3,   // Hangul syllables
             0xF900...0xFAFF,   // CJK compatibility ideographs
             0xFE30...0xFE6F,   // CJK compatibility forms
             0xFF00...0xFF60,   // full-width forms
             0xFFE0...0xFFE6:
            return 2
        default:
            return 1
        }
    }
}
