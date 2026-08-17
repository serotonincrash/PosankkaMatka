//
//  MapView.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import MapKit
import FoliBusUI

/// The map surface, `Equatable` so a `HomeView.body` re-evaluation (e.g. sheet
/// drag) doesn't re-run the `Map` content. `==` compares only rendered value
/// inputs — not the `camera`/`selectedStopID` bindings MapKit reads live — so a
/// detent drag skips `body`. Apply with `.equatable()`.
struct MapView: View, Equatable {
    @Binding var camera: MapCameraPosition
    @Binding var selectedStopID: Foli.Stop.ID?
    let displayedStops: [Foli.Stop]
    /// Stop IDs served by a boat route — rendered with a ferry glyph.
    let boatStopIDs: Set<Foli.Stop.ID>
    let drawnRoutePath: [CLLocationCoordinate2D]
    let routeStart: CLLocationCoordinate2D?
    let routeEnd: CLLocationCoordinate2D?
    let drawnRouteColor: Color
    /// Drawn route+direction identity, used in `==` to trigger redraws.
    let routeDrawKey: String?

    var body: some View {
        Map(position: $camera, selection: $selectedStopID) {
            UserAnnotation()
            mapContent
        }
    }

    @MapContentBuilder
    private var mapContent: some MapContent {
        if !drawnRoutePath.isEmpty {
            MapPolyline(coordinates: drawnRoutePath)
                .stroke(drawnRouteColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        if let start = routeStart {
            Annotation("Start", coordinate: start) {
                routeEndpointPin(systemImage: "smallcircle.filled.circle.fill")
            }
            .annotationTitles(.hidden)
        }
        if let end = routeEnd {
            Annotation("End", coordinate: end) {
                routeEndpointPin(systemImage: "flag.checkered")
            }
            .annotationTitles(.hidden)
        }
        ForEach(displayedStops) { stop in
            if let coordinate = stop.location?.toCLCoordinate() {
                // System Marker keeps MapKit's label decluttering (a compact bus
                // glyph when dense) and shows the stop name when selected.
                // TODO: Finnish stops use distinctive real-world signage;
                // explore representing that here (custom Annotation with a
                // Föli-style sign glyph) instead of the generic bus/boat glyphs.
                Marker(stop.name, systemImage: markerSystemImage(for: stop), coordinate: coordinate)
                    .tint(boatStopIDs.contains(stop.id) ? .blue : .red)
                    .tag(stop.id)
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
            .background(drawnRouteColor, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }

    // Compare only the rendered value inputs — NOT the bindings. Unchanged during
    // a detent drag → body skipped → the Map isn't reprocessed each frame.
    // `routeDrawKey` (the direction id that produced the path/pins) stands in for
    // the path + start/end, which all change together with the selected direction.
    static func == (lhs: MapView, rhs: MapView) -> Bool {
        lhs.routeDrawKey == rhs.routeDrawKey
            && lhs.drawnRouteColor == rhs.drawnRouteColor
            && lhs.displayedStops.map(\.id) == rhs.displayedStops.map(\.id)
            && lhs.boatStopIDs == rhs.boatStopIDs
    }
}
