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
    @ObservationIgnored
    var currentLocation: CLLocationCoordinate2D?
    var locationManager: CLLocationManager = CLLocationManager()
    
    override init() {
        super.init()
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.delegate = self
        if checkLocationAuthorization() {
            self.locationManager.startUpdatingLocation()
        } else {
            
        }
        
    }
    
    // thanks random medium page
    func checkLocationAuthorization() -> Bool {
        
        switch self.locationManager.authorizationStatus {
        case .notDetermined: //The user choose allow or denny your app to get the location yet
            self.locationManager.requestWhenInUseAuthorization()
            // The result of this will
            return false
        case .restricted://The user cannot change this app’s status, possibly due to active restrictions such as parental controls being in place.
            return false
            
        case .denied://The user dennied your app to get location or disabled the services location or the phone is in airplane mode
            return false
            
        case .authorizedAlways://This authorization allows you to use all location services and receive location events whether or not your app is in use.
            return true
        case .authorizedWhenInUse://This authorization allows you to use all location services and receive location events only when your app is in use
            if currentLocation == nil {
                currentLocation = self.locationManager.location?.coordinate
            }
            return true
        @unknown default:
            print("Location service disabled")
            return false
        }
    }
    
    func locationManagerDidChangeAuthorization(_ locationManager: CLLocationManager) {
        _ = checkLocationAuthorization()
    }
    
    func locationManager(_ locationManager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.first?.coordinate
    }
}
