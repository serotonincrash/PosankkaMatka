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

struct HomeView: View {
    /// Initial span when centering on the user's location.
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
    /// Span (degrees) at or below which markers show; further out, none.
    private static let markerThreshold: CLLocationDegrees = 0.06
    /// Street-level span for a stop selected while zoomed out.
    private static let selectionSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

    @State private var locationManager = LocationManager()
    @State private var stopsStore = ResourceStore<[Foli.Stop]>()
    @State private var routesStore = ResourceStore<[Foli.Route]>()
    @FoliService var foli

    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    /// Markers currently drawn; recomputed only on meaningful camera changes.
    @State private var displayedStops: [Foli.Stop] = []
    /// Region that produced `displayedStops`; skips no-op recomputes.
    @State private var lastMarkerRegion: MKCoordinateRegion?
    @State private var selectedStopID: Foli.Stop.ID?
    @State private var stop: StopWithDistance?
    /// Shared sheet detents, bound only by `SheetHost`; this view reads them
    /// solely in untracked framing methods (see `onCardDetentChange`).
    @State private var sheetModel = SheetModel()
    @State private var selectedRoute: Foli.Route?
    /// Per-direction route data + the selected direction, shared with the map
    /// and the card's `RouteDetailList`.
    @State private var routeDetail = RouteDetailStore()
    /// Live vehicles, polled while a detail card is open (scoped to it).
    @State private var vehicleStore = VehicleStore()
    /// Stop IDs served by a boat route — rendered with a ferry glyph.
    @State private var boatStopIDs: Set<Foli.Stop.ID> = []
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Map + sheets as ZStack SIBLINGS: the sheets (and their detent state)
        // live in `SheetHost`, so drag-churn never re-evaluates the Map, and
        // host-wide `presentationBackgroundInteraction` keeps the map tappable
        // behind them.
        ZStack {
            // The 0.5 s tick re-invokes only this MapView chain, feeding it
            // interpolated vehicle positions; camera + selection modifiers
            // stay attached to the Map itself.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                MapView(
                    camera: $camera,
                    selectedStopID: $selectedStopID,
                    displayedStops: displayedStops,
                    boatStopIDs: boatStopIDs,
                    direction: routeDetail.selectedDirection,
                    routeColor: selectedRoute?.color ?? .accentColor,
                    isZoomedIn: isZoomedIn,
                    routeIsSelected: selectedRoute != nil,
                    vehicles: vehicleStore.displayVehicles(at: context.date),
                    lineRoutes: lineRoutes
                )
                .ignoresSafeArea()
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    updateDisplayedStops(for: context.region)
                }
                .onChange(of: selectedStopID) { _, newValue in
                    // Tapping empty map (or the selected marker again) clears
                    // MapKit's selection — with a stop card up, that reads as
                    // "dismiss" (Maps-style). A stop over a route just pops the
                    // stop; X remains the full exit.
                    if newValue == nil, stop != nil {
                        stop = nil
                    } else {
                        handleStopSelection(newValue)
                    }
                }
                .onChange(of: stop) { _, newStop in
                    // Card dismissed: drop the marker highlight so the same stop is re-tappable.
                    if newStop == nil { selectedStopID = nil }
                    updateVehicleMonitoring()
                }
                .onChange(of: selectedRoute) { _, newRoute in
                    handleRouteSelection(newRoute)
                    updateVehicleMonitoring()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Live data; don't burn it in the background.
                vehicleStore.isPaused = phase != .active
            }

            SheetHost(
                selectedStopID: $selectedStopID,
                selectedRoute: $selectedRoute,
                stop: $stop,
                sheetModel: sheetModel,
                onCardDetentChange: reframeSelection
            )
        }
        .environment(locationManager)
        .environment(stopsStore)
        .environment(routesStore)
        .environment(routeDetail)
        .task {
            let foli = foli
            async let stops: Void = stopsStore.load { try await foli.fetchStops() }
            async let routes: Void = routesStore.load { try await foli.fetchRoutes() }
            _ = await (stops, routes)
            if let routes = routesStore.state.value {
                boatStopIDs = await Self.boatStopIDs(routes: routes, using: foli)
            }
            await centerOnUser()
        }
    }

    // MARK: - Map content

    private var allStops: [Foli.Stop] {
        stopsStore.state.value ?? []
    }

    /// The route per line number (SIRI `lineRef` == `route.shortName`, not the
    /// internal route id), for coloring live vehicle pins.
    private var lineRoutes: [String: Foli.Route] {
        Dictionary((routesStore.state.value ?? []).map { ($0.shortName, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Derived from `visibleRegion` (not the camera binding) so it also tracks
    /// programmatic camera moves.
    private var isZoomedIn: Bool {
        guard let span = visibleRegion?.span.latitudeDelta else { return false }
        return span <= Self.markerThreshold
    }

    // MARK: - Selection

    /// Presents the stop card and frames the stop above it. `selectedStopID`
    /// clears on dismissal, not here (that would drop the marker highlight).
    private func handleStopSelection(_ newValue: Foli.Stop.ID?) {
        guard let newValue,
              let found = allStops.first(where: { $0.id == newValue }),
              let coordinate = found.location?.toCLCoordinate() else { return }
        // A fresh card opens at the default detent; swaps keep the user's.
        if stop == nil && selectedRoute == nil { sheetModel.cardDetent = .medium }
        // Recenter BEFORE presenting the card: the concurrent sheet transition
        // can make MapKit skip the camera animation and drop the zoom.
        frameSelectedStop(at: coordinate)
        stop = StopWithDistance(found)
    }

    /// Loads the route's per-direction data; deselecting clears it.
    private func handleRouteSelection(_ route: Foli.Route?) {
        guard let route else {
            routeDetail.reset()
            return
        }
        let foli = foli
        // Cards are always fresh here (routes come from the lists): default detent.
        sheetModel.cardDetent = .medium
        Task {
            await routeDetail.load(routeId: route.id, using: foli)
            // Frame only on open; Picker switches just redraw the line/pins.
            frameSelectedDirection()
        }
    }

    /// Keeps vehicle polling in step with the open card (stop scope wins);
    /// no card open stops the poller.
    private func updateVehicleMonitoring() {
        if let stop {
            vehicleStore.start(.stop(stop.stop.id), using: foli)
        } else if let route = selectedRoute {
            vehicleStore.start(.line(route.shortName), using: foli)
        } else {
            vehicleStore.stopMonitoring()
        }
    }

    /// Reframes the selection for a changed card detent (stop card wins).
    /// Fired by `SheetHost` from untracked context — never read from `body`.
    private func reframeSelection() {
        if let coordinate = stop?.stop.location?.toCLCoordinate() {
            frameSelectedStop(at: coordinate)
        } else {
            frameSelectedDirection()
        }
    }

    /// Frames a stop above the card, keeping a deliberate close zoom or
    /// snapping to street level when zoomed out.
    private func frameSelectedStop(at coordinate: CLLocationCoordinate2D) {
        let currentSpan = visibleRegion?.span ?? Self.defaultSpan
        let span = currentSpan.latitudeDelta <= Self.markerThreshold ? currentSpan : Self.selectionSpan
        // Shift the center south so the stop sits above the card.
        let nudge = (1 - visibleFraction(for: sheetModel.cardDetent)) / 2
        let center = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * nudge,
            longitude: coordinate.longitude
        )
        let region = MKCoordinateRegion(center: center, span: span)
        visibleRegion = region
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(region)
        }
    }

    /// Frames the direction's path (or stop coords) above the route card —
    /// not centered behind it.
    private func frameSelectedDirection() {
        // The stop card wins: never re-frame the route over it.
        guard stop == nil, let direction = routeDetail.selectedDirection else { return }
        let coords = direction.path.isEmpty
            ? direction.stops.compactMap { $0.location?.toCLCoordinate() }
            : direction.path
        guard let region = MKCoordinateRegion(enclosing: coords) else { return }

        // Inflate the span by 1/fraction so the route occupies just the visible
        // strip, then shift the center south by the added height.
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
        withAnimation { camera = .region(framed) }
    }

    /// Fraction of map height visible above the card. `.large` frames like
    /// medium: fitting into its sliver would zoom out ~4× and flatten turns.
    private func visibleFraction(for detent: PresentationDetent) -> CGFloat {
        detent == .height(110) ? 0.85 : 0.5
    }

    // MARK: - Helpers

    /// Stop IDs served by a ferry route (GTFS `route_type` 4): ferry routes →
    /// trips → stop times. Failures skip a trip (bus fallback).
    private static func boatStopIDs(routes: [Foli.Route], using foli: FoliService) async -> Set<Foli.Stop.ID> {
        let ferryRouteIDs = routes.filter { $0.type == 4 }.map(\.id)
        guard !ferryRouteIDs.isEmpty else { return [] }
        var ids: Set<Foli.Stop.ID> = []
        for routeID in ferryRouteIDs {
            guard let trips = try? await foli.fetchTrips(forRoute: routeID) else { continue }
            for trip in trips {
                guard let stopTimes = try? await foli.fetchStopTimes(forTrip: trip.tripId) else { continue }
                ids.formUnion(stopTimes.compactMap(\.stopId))
            }
        }
        return ids
    }

    /// Refreshes markers for a settled region, skipping no-op changes (a detent
    /// change fires `onMapCameraChange` with a barely changed region).
    private func updateDisplayedStops(for region: MKCoordinateRegion) {
        let zoomedIn = region.span.latitudeDelta <= Self.markerThreshold
        // Zoomed out past the threshold: too dense — show none.
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

    /// Stops in the region's bounding box (bounded by `markerThreshold`);
    /// region-only membership keeps markers stable while panning.
    private func stopsInRegion(_ region: MKCoordinateRegion) -> [Foli.Stop] {
        let latRange = (region.center.latitude - region.span.latitudeDelta / 2)
            ... (region.center.latitude + region.span.latitudeDelta / 2)
        let lonRange = (region.center.longitude - region.span.longitudeDelta / 2)
            ... (region.center.longitude + region.span.longitudeDelta / 2)
        return allStops.within(latRange: latRange, lonRange: lonRange)
    }

    /// Centers on the user once a fix arrives (briefly polled; the map doesn't
    /// live-recenter).
    private func centerOnUser() async {
        guard locationManager.isAuthorized else { return }
        for _ in 0..<20 {
            if let coordinate = locationManager.currentLocation {
                // Shift south so the user sits above the sheet.
                let nudge = (1 - visibleFraction(for: sheetModel.listDetent)) / 2
                let center = CLLocationCoordinate2D(
                    latitude: coordinate.latitude - Self.defaultSpan.latitudeDelta * nudge,
                    longitude: coordinate.longitude
                )
                let region = MKCoordinateRegion(center: center, span: Self.defaultSpan)
                visibleRegion = region
                withAnimation { camera = .region(region) }
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return  // Task cancelled — stop polling.
            }
        }
    }
}

private extension MKCoordinateRegion {
    /// Enclosing region with padding, or nil if empty.
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

    /// Regions close enough to skip a marker recompute; epsilon scales with span.
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
}
