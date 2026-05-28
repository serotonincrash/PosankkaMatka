//
//  CLLocation+fromCoordinate2D.swift
//  PosankkaMatka
//
//  Created by sero on 8/4/26.
//

import Foundation
import CoreLocation
public extension CLLocation {
    convenience init?(_ coordinate2D: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate2D) else { return nil }
        self.init(latitude: coordinate2D.latitude, longitude: coordinate2D.longitude)
    }
}
