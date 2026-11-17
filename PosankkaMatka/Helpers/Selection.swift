//
//  Selection.swift
//  PosankkaMatka
//

import FoliBusUI

/// What the detail card shows. A stop and a route can both be set — a stop
/// opened from a route's list sits over that route, and closing the stop
/// returns to it. Nothing set means the master lists are up.
struct Selection: Equatable {
    var stop: Foli.Stop?
    var route: Foli.Route?

    /// No card: the master lists show.
    var isEmpty: Bool { stop == nil && route == nil }
}
