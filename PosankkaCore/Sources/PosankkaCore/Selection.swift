import FoliBusAPI

/// One detail card.
public enum Card: Hashable, Sendable {
    case stop(Foli.Stop)
    case route(Foli.Route)
    case vehicle(TripKey)
}

/// The detail cards as a stack; only the top one shows. Empty means no card.
public struct Selection: Equatable, Sendable {
    public private(set) var cards: [Card]

    public init(_ cards: [Card] = []) {
        self.cards = cards
    }

    public var isEmpty: Bool { cards.isEmpty }
    public var top: Card? { cards.last }

    /// The top card's stop, if it is a stop card.
    public var stop: Foli.Stop? {
        if case .stop(let stop) = top { stop } else { nil }
    }

    /// The top card's trip, if it is a vehicle card.
    public var vehicle: TripKey? {
        if case .vehicle(let key) = top { key } else { nil }
    }

    /// The topmost route card anywhere in the stack; its line stays drawn
    /// under cards pushed over it.
    public var route: Foli.Route? {
        for case .route(let route) in cards.reversed() { return route }
        return nil
    }

    /// Pushes `card`, unless it is already on top.
    public mutating func push(_ card: Card) {
        guard top != card else { return }
        cards.append(card)
    }

    /// Replaces a top card of the same kind, else pushes. Map taps use this so
    /// tapping marker after marker swaps rather than piling up cards.
    public mutating func pushReplacingSameKind(_ card: Card) {
        if let top, top.isSameKind(as: card) {
            cards[cards.count - 1] = card
        } else {
            push(card)
        }
    }

    /// A route opened from the lists starts a fresh stack.
    public mutating func openRoute(_ route: Foli.Route) {
        cards = [.route(route)]
    }

    public mutating func pop() {
        _ = cards.popLast()
    }

    public mutating func popAll() {
        cards.removeAll()
    }
}

extension Card {
    func isSameKind(as other: Card) -> Bool {
        switch (self, other) {
        case (.stop, .stop), (.route, .route), (.vehicle, .vehicle): true
        default: false
        }
    }
}
