//
//  MapView.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import MapKit
import FoliBusUI

/// The map surface, extracted from `HomeView` and made `Equatable` so that a
/// `HomeView.body` re-evaluation (e.g. the continuous `selectedDetent` writes
/// while dragging the sheet) does NOT re-run the `Map` / its content builder.
///
/// `==` compares only the value inputs the map renders; the `camera` and
/// `selectedStopID` bindings are intentionally excluded (they're stable across a
/// drag, and MapKit reads them live), so during a detent drag `==` returns true
/// and SwiftUI skips `body`. Apply with `.equatable()` at the call site.
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
    /// Identity of the drawn route+direction — used only in `==` so switching to
    /// a different route/direction still triggers a redraw of the line/pins.
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
                // TODO: Finnish bus stops use distinctive real-world signage;
                // explore representing that here (custom Annotation with a
                // Föli-style sign glyph) instead of the generic bus icon.
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
