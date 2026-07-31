/// The one line a 請示 block in a chat adds once the card is resolved.
///
/// The green outline says "handled", but it does not say *what was decided* —
/// reading the thread back, the owner had to open the card again to remember
/// which option he picked. This turns the resolved card into a sentence.
///
/// Pure and string-only: it takes the pieces of the answer rather than a
/// `ReplyCard`, so the logic-test runner can compile it. Two things it must
/// never do — invent a decision the card has not told us yet (a block that
/// reads 「已選」 with nothing behind it is worse than no line at all), and
/// crash on an index that outlived its options.
enum AnsweredCardSummary {
    /// The line for a resolved card, or `nil` when there is nothing honest to
    /// say — still waiting, an unknown status, or an answered card whose detail
    /// has not arrived yet.
    ///
    /// - Parameters:
    ///   - statusRaw: the wire status projected on the chat message.
    ///   - optionIdx: the index the owner picked, if he picked one.
    ///   - optionWording: the picked option's original wording. Only the light
    ///     list row carries it; the full card sends `options` instead.
    ///   - options: the full card's option list.
    ///   - ownText: the reply the owner typed himself.
    static func text(statusRaw: String?,
                     optionIdx: Int?,
                     optionWording: String?,
                     options: [String]?,
                     ownText: String?) -> String? {
        switch statusRaw {
        case "answered":
            if let option = chosenOption(optionIdx: optionIdx,
                                         optionWording: optionWording,
                                         options: options) {
                return "已選：" + AnswerConfirmationCopy.preview(of: option)
            }
            if let own = trimmed(ownText) {
                return "已回覆：" + AnswerConfirmationCopy.preview(of: own)
            }
            return nil
        case "expired":
            return "已過期"
        default:
            return nil
        }
    }

    /// The picked option's wording — the one resolver for every surface that
    /// names a decision (the chat block and 近期已處理 both call this).
    ///
    /// `optionWording` wins over the index. It is what the server recorded as
    /// picked at answer time, so it survives an edited option list, while an
    /// index only means anything against the exact list it was picked from. The
    /// light list row carries only the wording and the full card carries only
    /// the list, so in practice they never disagree — the order decides what
    /// happens when they do.
    ///
    /// An index past the end reads as "not known" rather than trapping: a stale
    /// index can outlive the card it came from.
    static func chosenOption(optionIdx: Int?,
                             optionWording: String?,
                             options: [String]?) -> String? {
        if let wording = trimmed(optionWording) { return wording }
        if let optionIdx, let options, options.indices.contains(optionIdx) {
            return trimmed(options[optionIdx])
        }
        return nil
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }
}
