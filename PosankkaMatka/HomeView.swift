//
//  HomeView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import CoreLocation
import MapKit
import FoliBusUI
import PosankkaCore

struct HomeView: View {
    /// ~1.7 km tall.
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    /// Latitude span above which stop markers are hidden (too dense).
    private static let markerThreshold: CLLocationDegrees = 0.06
    /// Street-level span for a stop selected while zoomed out.
    private static let selectionSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

    @Environment(AppModel.self) private var model
    /// Ties the overlay compass to the map.
    @Namespace private var mapScope

    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    /// Zoom and heading to keep when reframing; `visibleRegion`'s span is a
    /// bounding box, inflated when the map is rotated.
    @State private var liveCamera: MapCamera?
    @State private var displayedStops: [Foli.Stop] = []
    @State private var lastMarkerRegion: MKCoordinateRegion?
    /// Read here only outside `body`, so detent drags don't re-render the map.
    @State private var sheetModel = SheetModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Sheets are siblings of the map so detent drags don't re-render it.
        ZStack {
            // Ticks only the map, for interpolated vehicle positions.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                MapView(
                    camera: $camera,
                    selectedStopID: stopSelection,
                    mapScope: mapScope,
                    displayedStops: displayedStops,
                    boatStopIDs: model.boatStopIDs,
                    direction: model.routeDetail.selectedDirection,
                    routeColor: model.selection.route?.color ?? .accentColor,
                    isZoomedIn: isZoomedIn,
                    routeIsSelected: model.selection.route != nil,
                    vehicles: model.vehicles.displayVehicles(at: context.date),
                    lineRoutes: lineRoutes
                )
                .ignoresSafeArea(edges: .bottom)
                // Everything on the map is reachable through the sheets.
                .accessibilityHidden(true)
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    liveCamera = context.camera
                    updateDisplayedStops(for: context.region)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                model.vehicles.isPaused = phase != .active
            }

            VStack(spacing: 12) {
                MapLocateButton(isAuthorized: model.location.isAuthorized, action: recenterOnUser)
                MapCompass(scope: mapScope)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 16)
            .accessibilityHidden(true)

            SheetHost(
                selection: model.selection,
                selectedStopID: stopSelection,
                selectedRoute: routeSelection,
                sheetModel: sheetModel,
                onClose: model.closeCard,
                onCardDetentChange: reframeSelection
            )
        }
        .mapScope(mapScope)
        .task {
            await model.loadStopsAndRoutes()
            // After stops (the first region's markers need them), but not
            // after the slow ferry lookup.
            async let centered: Void = centerOnUser()
            await model.loadBoatStops()
            await centered
        }
    }

    // MARK: - Map content

    /// Routes by SIRI `lineRef` (the short name, not the route id).
    private var lineRoutes: [String: Foli.Route] {
        Dictionary((model.routes.state.value ?? []).map { ($0.shortName, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    private var isZoomedIn: Bool {
        guard let span = visibleRegion?.span.latitudeDelta else { return false }
        return span <= Self.markerThreshold
    }

    // MARK: - Selection

    /// MapKit sets nil when empty map or the selected marker is tapped,
    /// which pops the stop card.
    private var stopSelection: Binding<Foli.Stop.ID?> {
        Binding(
            get: { model.selection.stop?.id },
            set: { id in
                if let id { selectStop(id: id) } else { model.closeStop() }
            }
        )
    }

    private var routeSelection: Binding<Foli.Route?> {
        Binding(
            get: { model.selection.route },
            set: { route in
                if let route { selectRoute(route) } else { model.closeCard() }
            }
        )
    }

    private func selectStop(id: Foli.Stop.ID) {
        guard id != model.selection.stop?.id,
              let found = model.stop(withID: id),
              let coordinate = found.location?.toCLCoordinate() else { return }
        // Re-open at .medium, without the detent-change reframe: it would run
        // on stale camera state and undo the framing below.
        if sheetModel.cardDetent != .medium {
            sheetModel.suppressDetentReframe = true
            sheetModel.cardDetent = .medium
        }
        // Frame before presenting: during the sheet transition MapKit can
        // skip the camera animation and drop the zoom.
        frameSelectedStop(at: coordinate)
        model.selectStop(found)
    }

    private func selectRoute(_ route: Foli.Route) {
        sheetModel.cardDetent = .medium
        model.selectRoute(route, onLoaded: frameSelectedDirection)
    }

    /// Moves only the center, along the screen's vertical axis, keeping the
    /// live zoom and heading so rotated maps still seat above the sheet.
    private func moveCamera(anchor: CLLocationCoordinate2D, nudge: CGFloat) {
        guard let cam = liveCamera else { return }
        let heading = cam.heading * .pi / 180
        // Longitude degrees shrink with latitude.
        let scale = max(cos(anchor.latitude * .pi / 180), 0.2)
        // Bounding span = width·|sin h| + height·|cos h|; recover the height
        // assuming a portrait phone's ~2:1 aspect.
        let bbox = visibleRegion?.span.latitudeDelta ?? Self.defaultSpan.latitudeDelta
        let height = bbox / (abs(cos(heading)) + abs(sin(heading)) / 2)
        let (upEast, upNorth) = (sin(heading), cos(heading))
        let center = CLLocationCoordinate2D(
            latitude: anchor.latitude - nudge * height * upNorth,
            longitude: anchor.longitude - nudge * height * upEast / scale
        )
        withAnimation(reduceMotion ? nil : .default) {
            camera = .camera(MapCamera(
                centerCoordinate: center,
                distance: cam.distance,
                heading: cam.heading,
                pitch: cam.pitch
            ))
        }
    }

    /// Re-seats the selection above a user-dragged card (stop wins over route).
    private func reframeSelection() {
        let anchor: CLLocationCoordinate2D
        if let coordinate = model.selection.stop?.location?.toCLCoordinate() {
            anchor = coordinate
        } else if let direction = model.routeDetail.selectedDirection {
            let coords = direction.framingCoordinates.map { $0.toCLCoordinate() }
            guard let center = MKCoordinateRegion(enclosing: coords)?.center else { return }
            anchor = center
        } else {
            return
        }
        let nudge = (1 - visibleFraction(for: sheetModel.cardDetent)) / 2
        moveCamera(anchor: anchor, nudge: nudge)
    }

    /// Keeps the current zoom if close enough, else snaps to street level.
    private func frameSelectedStop(at coordinate: CLLocationCoordinate2D) {
        let currentSpan = visibleRegion?.span ?? Self.defaultSpan
        let span = currentSpan.latitudeDelta <= Self.markerThreshold ? currentSpan : Self.selectionSpan
        let nudge = (1 - visibleFraction(for: sheetModel.cardDetent)) / 2
        let center = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * nudge,
            longitude: coordinate.longitude
        )
        let region = MKCoordinateRegion(center: center, span: span)
        visibleRegion = region
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            camera = .region(region)
        }
    }

    private func frameSelectedDirection() {
        guard model.selection.stop == nil, let direction = model.routeDetail.selectedDirection else { return }
        let coords = direction.framingCoordinates.map { $0.toCLCoordinate() }
        guard let region = MKCoordinateRegion(enclosing: coords) else { return }

        // Grow the span so the route fits the strip above the card.
        let fraction = visibleFraction(for: sheetModel.cardDetent)
        let latDelta = region.span.latitudeDelta / fraction
        let addedLat = latDelta - region.span.latitudeDelta
        let framed = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.center.latitude - addedLat / 2,
                longitude: region.center.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: region.span.longitudeDelta)
        )
        visibleRegion = framed
        withAnimation(reduceMotion ? nil : .default) { camera = .region(framed) }
    }

    /// Approximate map fraction visible above the sheet. `.large` uses
    /// medium's: fitting its sliver would zoom out ~4×.
    private func visibleFraction(for detent: PresentationDetent) -> CGFloat {
        detent == SheetModel.peek ? 0.85 : 0.5
    }

    // MARK: - Helpers

    /// Skips near-identical regions (detent changes fire camera updates).
    private func updateDisplayedStops(for region: MKCoordinateRegion) {
        let zoomedIn = region.span.latitudeDelta <= Self.markerThreshold
        guard zoomedIn else {
            if !displayedStops.isEmpty { displayedStops = [] }
            lastMarkerRegion = region
            return
        }
        if let last = lastMarkerRegion, region.isApproximatelyEqual(to: last) {
            return
        }
        displayedStops = stopsInRegion(region)
        lastMarkerRegion = region
    }

    private func stopsInRegion(_ region: MKCoordinateRegion) -> [Foli.Stop] {
        let latRange = (region.center.latitude - region.span.latitudeDelta / 2)
            ... (region.center.latitude + region.span.latitudeDelta / 2)
        let lonRange = (region.center.longitude - region.span.longitudeDelta / 2)
            ... (region.center.longitude + region.span.longitudeDelta / 2)
        return model.allStops.within(latRange: latRange, lonRange: lonRange)
    }

    /// Waits up to 5 s for a first fix; the map doesn't follow the user.
    private func centerOnUser() async {
        guard model.location.isAuthorized else { return }
        for _ in 0..<20 {
            if let coordinate = model.location.currentLocation {
                let nudge = (1 - visibleFraction(for: sheetModel.listDetent)) / 2
                let center = CLLocationCoordinate2D(
                    latitude: coordinate.latitude - Self.defaultSpan.latitudeDelta * nudge,
                    longitude: coordinate.longitude
                )
                let region = MKCoordinateRegion(center: center, span: Self.defaultSpan)
                visibleRegion = region
                withAnimation(reduceMotion ? nil : .default) { camera = .region(region) }
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    private func recenterOnUser() {
        guard model.location.isAuthorized, let coordinate = model.location.currentLocation else { return }
        let detent = !model.selection.isEmpty ? sheetModel.cardDetent : sheetModel.listDetent
        moveCamera(anchor: coordinate, nudge: (1 - visibleFraction(for: detent)) / 2)
    }
}

/// Custom because the native button centers the user behind the sheets.
private struct MapLocateButton: View {
    let isAuthorized: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 44

    private var label: some View {
        Image(systemName: "location.fill")
            .font(.body.weight(.semibold))
            .foregroundStyle(isAuthorized ? Color.accentColor : Color.secondary)
            .frame(width: buttonSize, height: buttonSize)
    }

    var body: some View {
        Button(action: action) {
            if #available(iOS 26.0, *) {
                label.glassEffect(.regular.interactive(), in: Circle())
            } else {
                label
                    .background(Circle().fill(.background))
                    .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAuthorized)
        .accessibilityLabel("Show my location")
    }
}

private extension MKCoordinateRegion {
    /// Padded region around the coordinates; nil if empty.
    init?(enclosing coordinates: [CLLocationCoordinate2D]) {
        guard let first = coordinates.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coordinates {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.3, 0.005),
            longitudeDelta: max((maxLon - minLon) * 1.3, 0.005)
        )
        self.init(center: center, span: span)
    }

    func isApproximatelyEqual(to other: MKCoordinateRegion) -> Bool {
        let latEps = span.latitudeDelta * 0.05
        let lonEps = span.longitudeDelta * 0.05
        return abs(center.latitude - other.center.latitude) < latEps
            && abs(center.longitude - other.center.longitude) < lonEps
            && abs(span.latitudeDelta - other.span.latitudeDelta) < latEps
            && abs(span.longitudeDelta - other.span.longitudeDelta) < lonEps
    }
}

#Preview {
    HomeView()
        .environment(AppModel(client: DefaultFoliClientProvider().client()))
}
