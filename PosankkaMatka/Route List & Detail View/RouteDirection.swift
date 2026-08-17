//
//  RouteDirection.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import CoreLocation
import FoliBusUI

/// One direction of a route: `directionId`, headsign, ordered stops, and its shape path.
struct RouteDirection: Identifiable {
    let id: Int          // directionId (0 / 1)
    let headsign: String
    let stops: [Foli.Stop]
    /// The direction's drawn path (may be empty if its shape is unavailable).
    let path: [CLLocationCoordinate2D]

    /// The first stop's coordinate (route start pin).
    var start: CLLocationCoordinate2D? { stops.first?.location?.toCLCoordinate() }
    /// The last stop's coordinate (route end pin). Nil for a single-stop direction.
    var end: CLLocationCoordinate2D? {
        guard stops.count >= 2 else { return nil }
        return stops.last?.location?.toCLCoordinate()
    }
}

// `CLLocationCoordinate2D` isn't Hashable/Equatable, so conform manually on `id`
// (directionId is unique within a route; the struct is only used identified/tagged).
extension RouteDirection: Hashable {
    static func == (lhs: RouteDirection, rhs: RouteDirection) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
