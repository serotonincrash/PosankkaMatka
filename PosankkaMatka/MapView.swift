//
//  MapView.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import MapKit
import FoliBusUI

/// The map surface: user location, viewport stop markers, and — when a route is
/// selected — its polyline, start/end pins, and route stops (dots when zoomed out,
/// tappable markers when zoomed in).
struct MapView: View {
    @Binding var camera: MapCameraPosition
    @Binding var selectedStopID: Foli.Stop.ID?
    let displayedStops: [Foli.Stop]
    /// Stop IDs served by a boat route — rendered with a ferry glyph.
    let boatStopIDs: Set<Foli.Stop.ID>
    /// The selected route direction (its path + start/end pins), or nil when no
    /// route is selected.
    let direction: RouteDirection?
    /// The selected route's color, used for the polyline, stop dots, and markers.
    let routeColor: Color
    /// Whether the camera is zoomed in past the marker threshold — route stops
    /// render as tappable markers when true, else as simple dots.
    let isZoomedIn: Bool
    /// Whether a route is currently selected. Viewport markers show only when
    /// this is false (they must not leak through while a route is still loading).
    let routeIsSelected: Bool

    /// Zoom bounds (camera distance in meters): street level to region level.
    private static let minimumDistance: Double = 500
    private static let maximumDistance: Double = 50_000

    var body: some View {
        Map(
            position: $camera,
            bounds: MapCameraBounds(minimumDistance: Self.minimumDistance, maximumDistance: Self.maximumDistance),
            selection: $selectedStopID
        ) {
            UserAnnotation()
            mapContent
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
                // Use an offset identity (not `stop.id`) so these dots aren't
                // implicitly tagged and therefore remain non-selectable.
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
                Annotation("Start", coordinate: start) {
                    routeEndpointPin(systemImage: "smallcircle.filled.circle.fill")
                }
                .annotationTitles(.hidden)
            }
            if let end = direction.end {
                Annotation("End", coordinate: end) {
                    routeEndpointPin(systemImage: "flag.checkered")
                }
                .annotationTitles(.hidden)
            }
        }
        // Viewport markers only when no route is selected.
        if !routeIsSelected {
            ForEach(displayedStops) { stop in
                if let coordinate = stop.location?.toCLCoordinate() {
                    // System Marker keeps MapKit's label decluttering (a compact
                    // bus glyph when dense) and shows the stop name when selected.
                    // TODO: Finnish stops use distinctive real-world signage;
                    // explore representing that here (custom Annotation with a
                    // Föli-style sign glyph) instead of the generic bus/boat glyphs.
                    Marker(stop.name, systemImage: markerSystemImage(for: stop), coordinate: coordinate)
                        .tint(boatStopIDs.contains(stop.id) ? .blue : .red)
                        .tag(stop.id)
                }
            }
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

    /// A route stop, drawn as a small route-colored dot. Non-interactive — the
    /// zoomed-in markers are the tappable form.
    private var routeStopDot: some View {
        Circle()
            .fill(routeColor)
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }

}
