//
//  MapView.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import MapKit
import FoliBusUI
import PosankkaCore

/// What a map tap selects. Stop ids and vehicle refs are both strings, so
/// they need distinct tags.
enum MapItem: Hashable {
    case stop(Foli.Stop.ID)
    case vehicle(String)
}

/// A tracked bus's trip, split where the bus is.
struct JourneyOverlay {
    let travelled: [Foli.Coordinate]
    let remaining: [Foli.Coordinate]
    let calls: [VehicleJourney.Call]
    let color: Color
}

/// The map: user location, stop markers, the selected route, and live vehicles.
struct MapView: View {
    @Binding var camera: MapCameraPosition
    @Binding var selection: MapItem?
    /// Ties the map to the scoped compass in HomeView's overlay.
    var mapScope: Namespace.ID
    let displayedStops: [Foli.Stop]
    let boatStopIDs: Set<Foli.Stop.ID>
    let direction: RouteDirection?
    let routeColor: Color
    let isZoomedIn: Bool
    /// While a route or vehicle card is up (markers would show through during load).
    let hidesViewportStops: Bool
    /// Drawn instead of `direction` while a vehicle card is on top.
    let journey: JourneyOverlay?
    /// Vehicles with interpolated positions.
    let vehicles: [VehicleTracker.Position]
    /// Route per line number (`lineRef` == short name), for pin colors.
    let lineRoutes: [String: Foli.Route]
    let selectedVehicleRef: String?

    /// Camera distance bounds in meters.
    private static let minimumDistance: Double = 500
    private static let maximumDistance: Double = 50_000

    var body: some View {
        Map(
            position: $camera,
            bounds: MapCameraBounds(minimumDistance: Self.minimumDistance, maximumDistance: Self.maximumDistance),
            selection: $selection,
            scope: mapScope
        ) {
            UserAnnotation()
            mapContent
        }
        // Scale only: `.mapControls` can't host the compass, and its locate button centers behind the sheets.
        .mapControls {
            MapScaleView()
        }
    }

    @MapContentBuilder
    private var mapContent: some MapContent {
        if let direction {
            if !direction.path.isEmpty {
                MapPolyline(coordinates: direction.path.map { $0.toCLCoordinate() })
                    .stroke(routeColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if isZoomedIn {
                ForEach(direction.stops) { stop in
                    if let coordinate = stop.location?.toCLCoordinate() {
                        Marker(stop.name, systemImage: markerSystemImage(for: stop), coordinate: coordinate)
                            .tint(routeColor)
                            .tag(MapItem.stop(stop.id))
                    }
                }
            } else {
                // Untagged (offset identity) so dots aren't selectable.
                ForEach(Array(direction.stops.enumerated()), id: \.offset) { _, stop in
                    if let coordinate = stop.location?.toCLCoordinate() {
                        Annotation(stop.name, coordinate: coordinate) {
                            routeStopDot
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            if let start = direction.start {
                Annotation("Start", coordinate: start.toCLCoordinate()) {
                    routeEndpointPin(systemImage: "smallcircle.filled.circle.fill")
                }
                .annotationTitles(.hidden)
            }
            if let end = direction.end {
                Annotation("End", coordinate: end.toCLCoordinate()) {
                    routeEndpointPin(systemImage: "flag.checkered")
                }
                .annotationTitles(.hidden)
            }
        }
        if let journey {
            journeyContent(journey)
        }
        if !hidesViewportStops {
            ForEach(displayedStops) { stop in
                if let coordinate = stop.location?.toCLCoordinate() {
                    // System Marker for MapKit's label decluttering.
                    // TODO: model Föli's real stop signage instead of bus/boat glyphs.
                    Marker(stop.name, systemImage: markerSystemImage(for: stop), coordinate: coordinate)
                        .tint(boatStopIDs.contains(stop.id) ? .blue : .red)
                        .tag(MapItem.stop(stop.id))
                }
            }
        }
        // Positions arrive pre-interpolated.
        ForEach(vehicles) { displayed in
            Annotation(displayed.vehicle.publishedLineName,
                       coordinate: displayed.coordinate.toCLCoordinate(),
                       anchor: .center) {
                vehiclePin(for: displayed.vehicle, isSelected: displayed.id == selectedVehicleRef)
            }
            .annotationTitles(.hidden)
            .tag(MapItem.vehicle(displayed.id))
        }
    }

    @MapContentBuilder
    private func journeyContent(_ journey: JourneyOverlay) -> some MapContent {
        let lineStyle = StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
        if journey.travelled.count >= 2 {
            MapPolyline(coordinates: journey.travelled.map { $0.toCLCoordinate() })
                .stroke(Self.travelledColor, style: lineStyle)
        }
        if journey.remaining.count >= 2 {
            MapPolyline(coordinates: journey.remaining.map { $0.toCLCoordinate() })
                .stroke(journey.color, style: lineStyle)
        }
        let terminusID = journey.calls.last?.id
        ForEach(journey.calls) { call in
            if let coordinate = call.coordinate?.toCLCoordinate() {
                if call.id == terminusID {
                    Annotation(call.name, coordinate: coordinate) {
                        routeEndpointPin(systemImage: "flag.checkered", color: journey.color)
                    }
                    .annotationTitles(.hidden)
                    .tag(MapItem.stop(call.stopID))
                } else if call.state == .passed {
                    // Untagged: passed stops are context, not destinations.
                    Annotation(call.name, coordinate: coordinate) {
                        routeStopDot(color: Self.travelledColor)
                    }
                    .annotationTitles(.hidden)
                } else if isZoomedIn {
                    Marker(call.name, systemImage: boatStopIDs.contains(call.stopID) ? "ferry.fill" : "bus.fill",
                           coordinate: coordinate)
                        .tint(journey.color)
                        .tag(MapItem.stop(call.stopID))
                } else {
                    Annotation(call.name, coordinate: coordinate) {
                        routeStopDot(color: journey.color)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
    }

    private static let travelledColor = Color.gray.opacity(0.6)

    private func markerSystemImage(for stop: Foli.Stop) -> String {
        boatStopIDs.contains(stop.id) ? "ferry.fill" : "bus.fill"
    }

    private func routeEndpointPin(systemImage: String, color: Color? = nil) -> some View {
        Image(systemName: systemImage)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(8)
            .background(color ?? routeColor, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }

    private var routeStopDot: some View { routeStopDot(color: routeColor) }

    private func routeStopDot(color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    /// Shared so the hidden reference and visible text measure the same.
    private var puckFont: Font { .caption2.weight(.bold).monospaced() }

    /// Same idiom as `RouteBadge`.
    private func vehiclePin(for vehicle: Foli.VehicleLocation, isSelected: Bool) -> some View {
        let route = lineRoutes[vehicle.lineRef]
        return ZStack {
            Text("000")
                .font(puckFont)
                .hidden()
            Text(vehicle.lineRef)
                .font(puckFont)
                .foregroundStyle(route?.textColor ?? .white)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(route?.color ?? .accentColor, in: Capsule())
        .overlay(Capsule().stroke(.white, lineWidth: isSelected ? 3 : 1.5))
        .shadow(radius: isSelected ? 4 : 2)
        .scaleEffect(isSelected ? 1.4 : 1)
        // The capsule is ~20 pt tall; pad the tap target to 44.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(vehicleLabel(vehicle))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func vehicleLabel(_ vehicle: Foli.VehicleLocation) -> String {
        if let destination = vehicle.destinationName {
            String(localized: "Bus \(vehicle.lineRef) to \(destination)")
        } else {
            String(localized: "Bus \(vehicle.lineRef)")
        }
    }

}
