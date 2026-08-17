//
//  MapView.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import MapKit
import FoliBusUI

/// The map surface: user location, stop markers, and the selected route's
/// polyline + start/end pins.
struct MapView: View {
    @Binding var camera: MapCameraPosition
    @Binding var selectedStopID: Foli.Stop.ID?
    let displayedStops: [Foli.Stop]
    /// Stop IDs served by a boat route — rendered with a ferry glyph.
    let boatStopIDs: Set<Foli.Stop.ID>
    /// The selected route direction (its path + start/end pins), or nil when no
    /// route is selected.
    let direction: RouteDirection?
    /// The selected route's color, used for the polyline and endpoint pins.
    let routeColor: Color

    var body: some View {
        Map(position: $camera, selection: $selectedStopID) {
            UserAnnotation()
            mapContent
        }
    }

    @MapContentBuilder
    private var mapContent: some MapContent {
        if let direction, !direction.path.isEmpty {
            MapPolyline(coordinates: direction.path)
                .stroke(routeColor,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        if let start = direction?.start {
            Annotation("Start", coordinate: start) {
                routeEndpointPin(systemImage: "smallcircle.filled.circle.fill")
            }
            .annotationTitles(.hidden)
        }
        if let end = direction?.end {
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
            .background(routeColor, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(radius: 2)
    }

}
