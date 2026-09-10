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
    /// Span (degrees) at or below which markers show; further out the map draws
    /// none. Membership is purely in-view-and-zoomed-in, so markers don't churn
    /// while panning.
    private static let markerThreshold: CLLocationDegrees = 0.06
    /// Span the camera snaps to when a stop is selected while zoomed out — street
    /// level.
    private static let selectionSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

    @State private var locationManager = LocationManager()
    @State private var stopsStore = ResourceStore<[Foli.Stop]>()
    @State private var routesStore = ResourceStore<[Foli.Route]>()
    @FoliService var foli

    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    /// Markers currently drawn. Recomputed only on meaningful camera changes, not
    /// every body re-eval.
    @State private var displayedStops: [Foli.Stop] = []
    /// The region that produced `displayedStops`, used to skip no-op recomputes.
    @State private var lastMarkerRegion: MKCoordinateRegion?
    @State private var selectedStopID: Foli.Stop.ID?
    @State private var stop: StopWithDistance?
    /// Shared sheet detents, bound by `SheetHost`. Only `SheetHost` reads them in
    /// `body` — it re-evaluates per drag-frame write by design. This view touches
    /// them only in untracked framing methods, invoked via `onCardDetentChange`.
    @State private var sheetModel = SheetModel()
    @State private var selectedRoute: Foli.Route?
    /// Shared per-direction data (line + stops) and the selected direction, read
    /// by the map here and the pushed `RouteDetailList`.
    @State private var routeDetail = RouteDetailStore()
    /// Stop IDs served by a boat route — rendered with a ferry glyph on the map.
    @State private var boatStopIDs: Set<Foli.Stop.ID> = []

    var body: some View {
        // Map + the sheets as ZStack SIBLINGS. The sheets (and their detent
        // state) live in `SheetHost`, so drag-churn never re-evaluates this view /
        // the Map. `presentationBackgroundInteraction` is host-wide, so the map
        // stays undimmed and interactive behind the sheets despite being a
        // sibling.
        ZStack {
            MapView(
                camera: $camera,
                selectedStopID: $selectedStopID,
                displayedStops: displayedStops,
                boatStopIDs: boatStopIDs,
                direction: routeDetail.selectedDirection,
                routeColor: selectedRoute?.color ?? .accentColor,
                isZoomedIn: isZoomedIn,
                routeIsSelected: selectedRoute != nil
            )
            .ignoresSafeArea()
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                updateDisplayedStops(for: context.region)
            }
            .onChange(of: selectedStopID) { _, newValue in
                handleStopSelection(newValue)
            }
            .onChange(of: stop) { _, newStop in
                // Card dismissed: drop the marker highlight so the same stop is
                // re-tappable.
                if newStop == nil { selectedStopID = nil }
            }
            .onChange(of: selectedRoute) { _, newRoute in
                handleRouteSelection(newRoute)
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

    /// Whether the camera is zoomed in past `markerThreshold` (detailed markers show).
    /// Derived from `visibleRegion` so it also tracks programmatic camera moves.
    private var isZoomedIn: Bool {
        guard let span = visibleRegion?.span.latitudeDelta else { return false }
        return span <= Self.markerThreshold
    }

    // MARK: - Selection

    /// Presents the stop card and frames the stop in the visible area above it.
    /// `selectedStopID` is cleared in `.onChange(of: stop)` on dismissal, not here
    /// (which would drop the highlight).
    private func handleStopSelection(_ newValue: Foli.Stop.ID?) {
        guard let newValue,
              let found = allStops.first(where: { $0.id == newValue }),
              let coordinate = found.location?.toCLCoordinate() else { return }
        // A fresh card (nothing selected yet) opens at the default height;
        // swaps within an open card keep the user's chosen detent.
        if stop == nil && selectedRoute == nil { sheetModel.cardDetent = .medium }
        // Recenter BEFORE presenting the card: the concurrent sheet transition can
        // otherwise make MapKit skip the camera animation and drop the zoom.
        frameSelectedStop(at: coordinate)
        stop = StopWithDistance(found)
    }

    /// Loads the route's per-direction data; deselecting clears it.
    private func handleRouteSelection(_ route: Foli.Route?) {
        guard let route else {
            routeDetail.reset()   // direction becomes nil, clearing the drawn line + pins
            return
        }
        let foli = foli
        // Routes select from the lists, so the card is always fresh here: open
        // at the default height, not whatever the last card was left at.
        sheetModel.cardDetent = .medium
        Task {
            await routeDetail.load(routeId: route.id, using: foli)
            // Frame once, on initial open — Picker switches afterward don't move
            // the camera (only redraw the line/pins).
            frameSelectedDirection()
        }
    }

    /// Reframes the selection for a changed card detent — the stop card wins over
    /// the route card. Invoked by `SheetHost` (untracked context), never from
    /// `body`.
    private func reframeSelection() {
        if let coordinate = stop?.stop.location?.toCLCoordinate() {
            frameSelectedStop(at: coordinate)
        } else {
            frameSelectedDirection()
        }
    }

    /// Frames a stop in the map area above the stop card, keeping a deliberate
    /// close zoom or snapping to street level when zoomed out.
    private func frameSelectedStop(at coordinate: CLLocationCoordinate2D) {
        let currentSpan = visibleRegion?.span ?? Self.defaultSpan
        let span = currentSpan.latitudeDelta <= Self.markerThreshold ? currentSpan : Self.selectionSpan
        // Shift the center south so the stop sits in the visible area above the
        // card, using the card detent's visible fraction.
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

    /// Frames the selected direction's path (or stop coords) in the map area above
    /// the route card at its current detent — not centered behind it.
    private func frameSelectedDirection() {
        // The stop card wins: never re-frame the route over it.
        guard stop == nil, let direction = routeDetail.selectedDirection else { return }
        let coords = direction.path.isEmpty
            ? direction.stops.compactMap { $0.location?.toCLCoordinate() }
            : direction.path
        guard let region = MKCoordinateRegion(enclosing: coords) else { return }

        // Fit the route into the visible fraction above the route card: inflate
        // the span so the route occupies only that fraction, then shift the center
        // south (lower latitude) by the added height so it sits in the top part.
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

    /// Approximate fraction of the map height left visible above a sheet at a
    /// given detent. Peek leaves almost all of it; medium ~the top half. Large
    /// covers nearly everything — fitting into that sliver would explode the
    /// zoom (a route fit to a quarter of the screen zooms out ~4×, flattening
    /// its turns) — so it frames like medium and the camera holds still.
    private func visibleFraction(for detent: PresentationDetent) -> CGFloat {
        detent == .height(110) ? 0.85 : 0.5
    }

    // MARK: - Helpers

    /// Stop IDs served by a ferry route (GTFS `route_type` 4): walks ferry
    /// routes → trips → stop times. Failures skip a trip (bus fallback).
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

    /// Refreshes markers for a settled region, skipping when only the inset
    /// shifted (a sheet detent change fires `onMapCameraChange` with a barely
    /// changed region).
    private func updateDisplayedStops(for region: MKCoordinateRegion) {
        let zoomedIn = region.span.latitudeDelta <= Self.markerThreshold
        // Zoomed out past the threshold: too dense to draw/read — show none.
        guard zoomedIn else {
            if !displayedStops.isEmpty { displayedStops = [] }
            lastMarkerRegion = region
            return
        }
        // Skip if the region barely moved since the last marker computation.
        if let last = lastMarkerRegion, region.isApproximatelyEqual(to: last) {
            return
        }
        displayedStops = stopsInRegion(region)
        lastMarkerRegion = region
    }

    /// Stops within the region's bounding box. Called only past `markerThreshold`
    /// (so the count is bounded); membership depends only on the region, keeping
    /// markers stable while panning.
    private func stopsInRegion(_ region: MKCoordinateRegion) -> [Foli.Stop] {
        let latRange = (region.center.latitude - region.span.latitudeDelta / 2)
            ... (region.center.latitude + region.span.latitudeDelta / 2)
        let lonRange = (region.center.longitude - region.span.longitudeDelta / 2)
            ... (region.center.longitude + region.span.longitudeDelta / 2)
        return allStops.within(latRange: latRange, lonRange: lonRange)
    }

    /// Centers the initial camera on the user once a fix arrives (polled briefly,
    /// since `currentLocation` populates async). The map doesn't live-recenter.
    private func centerOnUser() async {
        guard locationManager.isAuthorized else { return }
        for _ in 0..<20 {
            if let coordinate = locationManager.currentLocation {
                // Shift the center south so the user sits in the visible area above
                // the sheet (the default detent is medium, covering the bottom half).
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
                return  // Task cancelled (view disappeared) — stop polling.
            }
        }
    }
}

private extension MKCoordinateRegion {
    /// A region enclosing all coordinates with padding, or nil if empty. Used to
    /// frame a selected route's polyline.
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

    /// True when two regions are close enough to skip a marker recompute. Epsilon
    /// scales with the span.
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
