/// Stable identity for the detail navigation stack.
///
/// SwiftUI constructor inputs are not view identity. Including the selected
/// item ID here makes three consecutive selections three distinct detail
/// lifetimes, so their local `@State` and initial `.task` cannot be reused.
struct IPadSplitDetailIdentity: Hashable {
    enum Kind: String, Hashable {
        case ask
        case task
        case peer
        case monitor
        case more
    }

    let kind: Kind
    let itemID: String?
}
