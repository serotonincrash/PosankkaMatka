//
//  StopWithDistance.swift
//  PosankkaMatka
//
//  Created by sero on 10/4/26.
//

import Foundation
import FoliBusAPI

struct StopWithDistance: Identifiable, Equatable {
    var id: String { stop.id }
    var stop: Foli.Stop

    var distance: Double?

    init(_ stop: Foli.Stop, distance: Double? = nil) {
        self.stop = stop
        self.distance = distance
    }

    var distanceText: String? {
        guard let distance else { return nil }
        return distance.rounded().formattedDistance
    }

    /// VoiceOver row label.
    var spokenDescription: String {
        if let distanceText {
            return String(localized: "Stop ID \(stop.id), \(stop.name), \(distanceText) away")
        }
        return String(localized: "Stop ID \(stop.id), \(stop.name)")
    }
}
