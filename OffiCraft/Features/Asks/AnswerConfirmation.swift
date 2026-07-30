import SwiftUI

/// A reply the owner has tapped but not yet confirmed.
///
/// Tapping an option used to send it immediately. The inbox is newest-first, so
/// a card arriving over SSE inserts at the top and pushes the rows below it
/// down — under the owner's finger. One confirmation step means a shifted row
/// costs a cancel, not a decision the member then acts on.
struct PendingAnswer {
    let card: ReplyCard
    let optionIdx: Int

    /// Empty when the list-level card has not been hydrated yet; the dialog
    /// then falls back to copy that does not pretend to quote an option. The
    /// resolution itself is in `AnswerConfirmationCopy` so it can be tested.
    var optionText: String {
        AnswerConfirmationCopy.optionText(options: card.options, optionIdx: optionIdx)
    }
}

extension View {
    /// One dialog for every place an option can be tapped, so the guard cannot
    /// be present on one screen and missing on another.
    ///
    /// ⚠️ Attach this in the same context as the tap it guards. A dialog
    /// declared on a screen that closes itself on tap goes down with it: it
    /// never presents, and the staged answer never clears — the next visit to
    /// that screen then opens with a stale confirmation already up.
    func answerConfirmation(
        _ pending: Binding<PendingAnswer?>,
        onConfirm: @escaping (PendingAnswer) -> Void
    ) -> some View {
        confirmationDialog(
            AnswerConfirmationCopy.title,
            isPresented: Binding(
                get: { pending.wrappedValue != nil },
                set: { if !$0 { pending.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            // `presenting:` keeps the staged answer alive for the closing
            // frame; reading the binding directly would recompute the message
            // from nil as the dialog goes away.
            presenting: pending.wrappedValue
        ) { answer in
            Button(AnswerConfirmationCopy.confirm) {
                onConfirm(answer)
                pending.wrappedValue = nil
            }
            Button(AnswerConfirmationCopy.cancel, role: .cancel) {
                pending.wrappedValue = nil
            }
        } message: { answer in
            Text(AnswerConfirmationCopy.message(option: answer.optionText))
        }
    }
}
