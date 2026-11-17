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

/// The map: user location, stop markers, the selected route, and live vehicles.
struct MapView: View {
    @Binding var camera: MapCameraPosition
    @Binding var selectedStopID: Foli.Stop.ID?
    /// Ties the map to the scoped compass in HomeView's overlay.
    var mapScope: Namespace.ID
    let displayedStops: [Foli.Stop]
    let boatStopIDs: Set<Foli.Stop.ID>
    let direction: RouteDirection?
    let routeColor: Color
    let isZoomedIn: Bool
    /// Viewport markers hide while a route is selected (they'd show through during load).
    let routeIsSelected: Bool
    /// Vehicles with interpolated positions.
    let vehicles: [VehicleTracker.Position]
    /// Route per line number (`lineRef` == short name), for pin colors.
    let lineRoutes: [String: Foli.Route]

    /// Camera distance bounds in meters.
    private static let minimumDistance: Double = 500
    private static let maximumDistance: Double = 50_000

    var body: some View {
        Map(
            position: $camera,
            bounds: MapCameraBounds(minimumDistance: Self.minimumDistance, maximumDistance: Self.maximumDistance),
            selection: $selectedStopID,
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
                            .tag(stop.id)
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
        if !routeIsSelected {
            ForEach(displayedStops) { stop in
                if let coordinate = stop.location?.toCLCoordinate() {
                    // System Marker for MapKit's label decluttering.
                    // TODO: model Föli's real stop signage instead of bus/boat glyphs.
                    Marker(stop.name, systemImage: markerSystemImage(for: stop), coordinate: coordinate)
                        .tint(boatStopIDs.contains(stop.id) ? .blue : .red)
                        .tag(stop.id)
                }
            }
        }
        // Untagged so they aren't selectable; positions arrive pre-interpolated.
        ForEach(vehicles) { displayed in
            Annotation(displayed.vehicle.publishedLineName, coordinate: displayed.coordinate.toCLCoordinate()) {
                vehiclePin(for: displayed.vehicle)
            }
            .annotationTitles(.hidden)
        }
    }

    private func markerSystemImage(for stop: Foli.Stop) -> String {
        boatStopIDs.contains(stop.id) ? "ferry.fill" : "bus.fill"
    }

    private func routeEndpointPin(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(8)
            .background(routeColor, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }

    private var routeStopDot: some View {
        Circle()
            .fill(routeColor)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    /// Shared so the hidden reference and visible text measure the same.
    private var puckFont: Font { .caption2.weight(.bold).monospaced() }

    /// Same idiom as `RouteBadge`.
    private func vehiclePin(for vehicle: Foli.VehicleLocation) -> some View {
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
            .overlay(Capsule().stroke(.white, lineWidth: 1.5))
            .shadow(radius: 2)
    }

}
