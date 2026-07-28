import Foundation

// Typed navigation targets.
//
// `navigationDestination(item:)` keys on the value's TYPE, so two destinations
// of the same type inside one stack collide — the second is ignored and taps
// land on the wrong screen. Since every id here is a String, each destination
// gets its own wrapper.

/// A reply card, by id.
struct CardRoute: Hashable, Identifiable {
    let id: String
}

/// A task, by id.
struct TaskRoute: Hashable, Identifiable {
    let id: String

    init(id: String) { self.id = id }
    init(_ ref: TaskRef) { self.id = ref.id }
}

/// A chat peer — member or outsource worker — by id.
struct PeerRoute: Hashable, Identifiable {
    let id: String
    /// Scroll to this message on arrival (jumping to a card's 原訊息).
    var highlightMessageId: String?
}
