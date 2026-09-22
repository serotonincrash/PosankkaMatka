//
//  StopWithDistance.swift
//  PosankkaMatka
//
//  Created by sero on 10/4/26.
//

import FoliBusAPI

struct StopWithDistance: Identifiable, Hashable {
    var id: String { stop.id }
    var stop: Foli.Stop
    
    var distance: Double?
    
    init(_ stop: Foli.Stop) {
        self.stop = stop
    }
    
    init(_ stop: Foli.Stop, distance: Double) {
        self.stop = stop
        self.distance = distance
    }

    /// Distance for display, or `nil` when unset (e.g. search results).
    var distanceText: String? {
        guard let distance else { return nil }
        return distance.rounded().formattedDistance
    }

    /// Row label for screen readers; distance included when known.
    var spokenDescription: String {
        if let distanceText {
            return "Stop ID \(stop.id), \(stop.name), \(distanceText) away"
        }
        return "Stop ID \(stop.id), \(stop.name)"
    }
}
