//
//  StopWithDistance.swift
//  PosankkaMatka
//
//  Created by sero on 10/4/26.
//

import FoliBusAPI

struct StopWithDistance: Identifiable {
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
}
