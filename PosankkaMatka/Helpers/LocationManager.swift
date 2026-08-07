//
//  LocationManager.swift
//  PosankkaMatka
//
//  Created by sero on 7/4/26.
//

import Foundation
import CoreLocation
internal import Combine

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate  {
    /// The most recent coordinate. Observable, so views showing distances update as
    /// the user moves. `distanceFilter` below bounds how often that happens.
    var currentLocation: CLLocationCoordinate2D?

    /// Current authorization, mirrored into observable state by the delegate so
    /// views can read it without touching `CLLocationManager`.
    private(set) var isAuthorized: Bool = false

    /// Not observable: it's a mutable reference type whose own properties SwiftUI
    /// can't track, and reading it from a `body` registered a spurious dependency.
    @ObservationIgnored
    var locationManager: CLLocationManager = CLLocationManager()

    override init() {
        super.init()
        self.locationManager.delegate = self
        self.locationManager.activityType = .otherNavigation
        self.locationManager.distanceFilter = 5
        self.locationManager.requestWhenInUseAuthorization()
        // Seed from the current status; the delegate keeps it current afterward.
        refreshAuthorization()
    }

    /// A pure read — no side effects, safe to call from a `body`.
    ///
    /// Previously this both mutated `currentLocation` and could trigger an
    /// authorization request, which meant rendering a view could change model
    /// state. Starting/stopping updates now lives in `refreshAuthorization()`,
    /// driven by the delegate.
    func checkLocationAuthorization() -> Bool {
        isAuthorized
    }

    /// Recomputes `isAuthorized` from the system status and starts or stops
    /// location updates to match.
    private func refreshAuthorization() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isAuthorized = true
            if currentLocation == nil {
                currentLocation = locationManager.location?.coordinate
            }
            locationManager.startUpdatingLocation()
        case .notDetermined, .restricted, .denied:
            isAuthorized = false
            locationManager.stopUpdatingLocation()
        @unknown default:
            isAuthorized = false
            locationManager.stopUpdatingLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ locationManager: CLLocationManager) {
        refreshAuthorization()
    }

    func locationManager(_ locationManager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
    }
}
