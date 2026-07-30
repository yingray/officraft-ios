/// The words on the "really send this reply?" dialog.
///
/// Answering a card is one tap and it closes the card on the server, so the
/// dialog exists to make sure the tap was meant — and it has to name the option
/// it is about to send, or confirming is as blind as the mis-tap it prevents.
///
/// Pure and string-only so the copy is testable: the logic-test runner compiles
/// this file, it cannot compile the view.
enum AnswerConfirmationCopy {
    static let confirm = "送出回覆"
    static let cancel = "取消"
    static let title = "送出這個回覆？"

    /// The dialog is a small sheet on a phone, so a long option is trimmed —
    /// but always at a length that still identifies which option it was.
    static let optionPreviewLimit = 70

    static func message(option: String) -> String {
        let trimmed = option.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "送出後這張請示就關閉了，成員會照這個回覆繼續。"
        }
        return "「\(preview(of: trimmed))」\n送出後這張請示就關閉了，成員會照這個回覆繼續。"
    }

    static func preview(of option: String) -> String {
        guard option.count > optionPreviewLimit else { return option }
        return String(option.prefix(optionPreviewLimit)) + "…"
    }

    /// The option a staged index points at, or "" when there is none.
    ///
    /// A list-level card carries no options until it is hydrated, and a stale
    /// index can outlive the card it came from — either way this has to answer
    /// with the fallback rather than trap. It lives here, not on the view's
    /// `PendingAnswer`, because this file is the one the logic-test runner
    /// compiles: an index guard nobody can test is exactly the kind of thing
    /// that silently stops holding.
    static func optionText(options: [String]?, optionIdx: Int) -> String {
        guard let options, options.indices.contains(optionIdx) else { return "" }
        return options[optionIdx]
    }
}
