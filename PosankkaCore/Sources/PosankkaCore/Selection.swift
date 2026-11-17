import FoliBusAPI

/// What the detail card shows. Both set means a stop opened from a route's
/// list; closing the stop returns to the route. Neither means no card.
public struct Selection: Equatable, Sendable {
    public var stop: Foli.Stop?
    public var route: Foli.Route?

    public init(stop: Foli.Stop? = nil, route: Foli.Route? = nil) {
        self.stop = stop
        self.route = route
    }

    public var isEmpty: Bool { stop == nil && route == nil }
}
