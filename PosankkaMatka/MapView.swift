//
//  MapView.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import MapKit
import FoliBusUI

/// The map surface: user location, viewport stop markers, the selected route's
/// line/pins/stops, and live vehicle pucks.
struct MapView: View {
    @Binding var camera: MapCameraPosition
    @Binding var selectedStopID: Foli.Stop.ID?
    /// Associates the map with the scoped compass in HomeView's controls
    /// overlay (bound there via `.mapScope`).
    var mapScope: Namespace.ID
    let displayedStops: [Foli.Stop]
    /// Stop IDs served by a boat route — rendered with a ferry glyph.
    let boatStopIDs: Set<Foli.Stop.ID>
    /// The selected route direction, or nil when none.
    let direction: RouteDirection?
    /// The selected route's color, used for the polyline, stop dots, and markers.
    let routeColor: Color
    /// Zoomed past the threshold: route stops render as tappable markers, else dots.
    let isZoomedIn: Bool
    /// Viewport markers show only when false (they'd leak through while a route loads).
    let routeIsSelected: Bool
    /// Live vehicles (SIRI VM) with their interpolated draw positions, shown
    /// while a detail card is open.
    let vehicles: [DisplayedVehicle]
    /// The route per line number (SIRI `lineRef` == short name), for pin colors.
    let lineRoutes: [String: Foli.Route]

    /// Zoom bounds (camera distance in meters): street level to region level.
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
        // Scale only: the compass + locate button live in HomeView's overlay
        // (`.mapControls` hosts no custom views, and its locate button
        // centers the user behind the sheets).
        .mapControls {
            MapScaleView()
        }
    }

    @MapContentBuilder
    private var mapContent: some MapContent {
        if let direction {
            if !direction.path.isEmpty {
                MapPolyline(coordinates: direction.path)
                    .stroke(routeColor,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            // Route stops: dots at overview zoom, tappable markers when zoomed in.
            if isZoomedIn {
                ForEach(direction.stops) { stop in
                    if let coordinate = stop.location?.toCLCoordinate() {
                        Marker(stop.name, systemImage: markerSystemImage(for: stop), coordinate: coordinate)
                            .tint(routeColor)
                            .tag(stop.id)
                    }
                }
            } else {
                // Offset identity: untagged, so the dots stay non-selectable.
                ForEach(Array(direction.stops.enumerated()), id: \.offset) { _, stop in
                    if let coordinate = stop.location?.toCLCoordinate() {
                        Annotation(stop.name, coordinate: coordinate) {
                            // Ambient summary at overview zoom — the tappable
                            // markers carry the accessible stop identity.
                            routeStopDot
                                .accessibilityHidden(true)
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            if let start = direction.start {
                Annotation("Start", coordinate: start) {
                    routeEndpointPin(systemImage: "smallcircle.filled.circle.fill")
                        .accessibilityLabel("Route start")
                }
                .annotationTitles(.hidden)
            }
            if let end = direction.end {
                Annotation("End", coordinate: end) {
                    routeEndpointPin(systemImage: "flag.checkered")
                        .accessibilityLabel("Route end")
                }
                .annotationTitles(.hidden)
            }
        }
        // Viewport markers only when no route is selected.
        if !routeIsSelected {
            ForEach(displayedStops) { stop in
                if let coordinate = stop.location?.toCLCoordinate() {
                    // System Marker: MapKit's label decluttering + selected name.
                    // TODO: model Föli's real stop signage instead of bus/boat glyphs.
                    Marker(stop.name, systemImage: markerSystemImage(for: stop), coordinate: coordinate)
                        .tint(boatStopIDs.contains(stop.id) ? .blue : .red)
                        .tag(stop.id)
                }
            }
        }
        // Vehicles last, on top; untagged (non-selectable). The store
        // interpolates positions between polls, so these arrive pre-blended.
        ForEach(vehicles) { displayed in
            Annotation(displayed.vehicle.publishedLineName, coordinate: displayed.coordinate) {
                vehiclePin(for: displayed.vehicle)
            }
            .annotationTitles(.hidden)
        }
    }

    /// Marker glyph per stop: boat stops get a ferry glyph, everything else a bus.
    private func markerSystemImage(for stop: Foli.Stop) -> String {
        boatStopIDs.contains(stop.id) ? "ferry.fill" : "bus.fill"
    }

    /// A route start/end pin glyph in the route color, distinct from stop markers.
    private func routeEndpointPin(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.headline)
            .foregroundStyle(.white)
            .padding(8)
            .background(routeColor, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }

    /// Route-colored dot; the zoomed-in markers are the tappable form.
    private var routeStopDot: some View {
        Circle()
            .fill(routeColor)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

    /// Shared monospaced puck font, so the hidden reference and visible text
    /// measure identically (same trick as `RouteBadge`).
    private var puckFont: Font { .caption2.weight(.bold).monospaced() }

    /// Vehicle puck: the `RouteBadge` idiom — hidden "000" reserves a
    /// three-digit width, longer codes (e.g. "Lautta") expand naturally.
    /// Stroke + shadow lift it off the line.
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
            .accessibilityLabel("Line \(vehicle.lineRef) vehicle")
    }

}
