//
//  StopWithDistance.swift
//  PosankkaMatka
//
//  Created by sero on 10/4/26.
//

import FoliBusAPI

struct StopWithDistance: Identifiable, Hashable {
    var id: String { stop.id }
    /// The stop this type encapsulates.
    var stop: Foli.Stop
    
    /// The distance from the user, in meters.
    var distance: Double?
    
    init(_ stop: Foli.Stop) {
        self.stop = stop
    }
    
    init(_ stop: Foli.Stop, distance: Double) {
        self.stop = stop
        self.distance = distance
    }

    /// Human-readable distance for row display, or `nil` when no distance is set
    /// (e.g. search results, where proximity isn't meaningful).
    var distanceText: String? {
        guard let distance else { return nil }
        return distance < 1000
            ? "\(Int(distance)) m"
            : "\((distance / 1000).formatted(toDecimalPlaces: 2)) km"
    }
}
