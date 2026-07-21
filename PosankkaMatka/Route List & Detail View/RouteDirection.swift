//
//  RouteDirection.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import FoliBusUI

/// One direction of a route: its GTFS `directionId`, the trip headsign that names
/// it (e.g. "Kauppatori"), and the ordered stops served in that direction.
struct RouteDirection: Identifiable, Hashable {
    let id: Int          // directionId (0 / 1)
    let headsign: String
    let stops: [Foli.Stop]
}
