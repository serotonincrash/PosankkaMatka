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
    /// Latitude span (degrees) at or below which markers are shown. When zoomed
    /// out past this the region holds too many stops to draw or read, so the map
    /// shows none until the user zooms in. A stop is simply in-view-and-zoomed-in
    /// or not — no per-pan ranking, so markers don't churn while panning.
    private static let markerThreshold: CLLocationDegrees = 0.06
    /// Span the camera snaps to when selecting a stop while zoomed out past the
    /// marker threshold — street level, showing the stop and its immediate
    /// surrounding streets/nearby stops.
    private static let selectionSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

    @State private var locationManager = LocationManager()
    @State private var stopsStore = ResourceStore<[Foli.Stop]>()
    @State private var routesStore = ResourceStore<[Foli.Route]>()
    @FoliService var foli

    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    /// The markers currently drawn. Recomputed only when the region meaningfully
    /// changes (see `onMapCameraChange`), NOT on every `body` re-eval — so a
    /// detent/inset change doesn't rebuild hundreds of markers and hitch.
    @State private var displayedStops: [Foli.Stop] = []
    /// The region that produced `displayedStops`, used to skip no-op recomputes.
    @State private var lastMarkerRegion: MKCoordinateRegion?
    @State private var selectedStopID: Foli.Stop.ID?
    @State private var stop: StopWithDistance?
    /// Shared sheet detent. Owned here, bound by `SheetHost`, and read by route
    /// framing (in methods only — NEVER in `body`, which would re-subscribe to
    /// per-drag-frame writes and bring back the detent hitch).
    @State private var sheetModel = SheetModel()
    @State private var selectedRoute: Foli.Route?
    /// Shared per-direction data (line + stops) and the selected direction, read
    /// by the map here and the pushed `RouteDetailList`.
    @State private var routeDetail = RouteDetailStore()
    /// Maps stops to their vehicle mode (bus/boat) for the map markers.
    @State private var stopTypes = StopTypeProvider()

    // Cached route-draw state. `mapContent` reads ONLY these (never
    // `routeDetail.selectedDirection` live), so a detent-drag body re-eval reuses
    // stable values instead of re-diffing the polyline every frame. Updated in
    // `updateDrawnRoute()` on real direction/route changes — same discipline as
    // `displayedStops`.
    @State private var drawnRoutePath: [CLLocationCoordinate2D] = []
    @State private var routeStart: CLLocationCoordinate2D?
    @State private var routeEnd: CLLocationCoordinate2D?
    @State private var drawnRouteColor: Color = .accentColor
    /// Identity of the drawn route+direction ("routeId:directionId", nil = none);
    /// MapView uses it in `==` to detect when the drawn line must change.
    @State private var routeDrawKey: String?

    var body: some View {
        // Map + the sheet as ZStack SIBLINGS. The sheet (and its detent state)
        // lives in `SheetHost`, so drag-churn never re-evaluates this view / the
        // Map. `presentationBackgroundInteraction` is host-wide, so the map stays
        // undimmed and interactive behind the sheet despite being a sibling.
        ZStack {
            MapView(
                camera: $camera,
                selectedStopID: $selectedStopID,
                displayedStops: displayedStops,
                boatStopIDs: stopTypes.boatStopIDs,
                drawnRoutePath: drawnRoutePath,
                routeStart: routeStart,
                routeEnd: routeEnd,
                drawnRouteColor: drawnRouteColor,
                routeDrawKey: routeDrawKey
            )
            .equatable()
            .ignoresSafeArea()
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                updateDisplayedStops(for: context.region)
            }
            .onChange(of: selectedStopID) { _, newValue in
                handleStopSelection(newValue)
            }
            .onChange(of: stop) { _, newStop in
                // Returned to the list: drop the marker highlight so the same
                // stop is re-tappable.
                if newStop == nil { selectedStopID = nil }
            }
            .onChange(of: selectedRoute) { _, newRoute in
                handleRouteSelection(newRoute)
            }
            // Redraw the line/pins for the newly selected direction, but do NOT
            // move the camera — a Picker switch keeps the map where it is. Camera
            // framing happens only on the initial route open (handleRouteSelection).
            .onChange(of: routeDetail.selectedDirectionId) { _, _ in
                updateDrawnRoute()
            }

            SheetHost(
                selectedStopID: $selectedStopID,
                selectedRoute: $selectedRoute,
                stop: $stop,
                showingDetail: showingDetail,
                sheetModel: sheetModel
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
                await stopTypes.load(routes: routes, using: foli)
            }
            await centerOnUser()
        }
    }

    // MARK: - Map content

    private var allStops: [Foli.Stop] {
        stopsStore.state.value ?? []
    }

    // MARK: - Selection

    /// Tapping a stop opens its `StopView`, keeps the marker highlighted,
    /// recenters the map on it (keeping the current zoom), and raises the sheet
    /// to `.medium` so the detail isn't obscured at the peek. The target is
    /// nudged south so the stop lands in the visible strip above the sheet — the
    /// map carries no sheet inset (that caused a detent hitch), so we offset only
    /// here, once. `selectedStopID` is *not* cleared here (that would drop the
    /// highlight); it's cleared in `onChange(of: stop)` when the user returns.
    private func handleStopSelection(_ newValue: Foli.Stop.ID?) {
        guard let newValue,
              let found = allStops.first(where: { $0.id == newValue }),
              let coordinate = found.location?.toCLCoordinate() else { return }
        // Preserve a deliberate close zoom (already within the marker threshold),
        // but snap to a fixed level when zoomed out — otherwise recentering at a
        // wide span leaves the selected stop with no visible markers.
        let currentSpan = visibleRegion?.span ?? Self.defaultSpan
        let span = currentSpan.latitudeDelta <= Self.markerThreshold ? currentSpan : Self.selectionSpan
        // Shift the center south by a quarter-span so the stop sits above the
        // (roughly half-screen) sheet when it's expanded.
        let center = CLLocationCoordinate2D(
            latitude: coordinate.latitude - span.latitudeDelta * 0.25,
            longitude: coordinate.longitude
        )
        // Animate the camera move on its own transaction so the concurrent
        // navigation push / detent change don't cause MapKit to skip it.
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
        // Detent raise is centralized in `.onChange(of: showingDetail)`.
        stop = StopWithDistance(found)
    }

    /// Whether a detail (stop or route) is currently pushed — drives the detent.
    private var showingDetail: Bool { stop != nil || selectedRoute != nil }

    /// Selecting a route loads its per-direction data (the map draws the selected
    /// direction; framing follows `selectedDirectionId`). Deselecting clears it.
    private func handleRouteSelection(_ route: Foli.Route?) {
        guard let route else {
            routeDetail.reset()
            updateDrawnRoute()   // clears the cached line + pins
            return
        }
        let foli = foli
        Task {
            await routeDetail.load(routeId: route.id, using: foli)
            // Frame once, on initial open — Picker switches afterward don't move
            // the camera (only redraw the line/pins).
            frameSelectedDirection()
        }
    }

    /// Copies the selected direction's path/endpoints/color into cached `@State`
    /// so `mapContent` never reads `routeDetail` live (avoids re-diffing the
    /// polyline on detent-drag body re-evals). Call on direction/route change.
    private func updateDrawnRoute() {
        guard let direction = routeDetail.selectedDirection else {
            drawnRoutePath = []
            routeStart = nil
            routeEnd = nil
            routeDrawKey = nil
            return
        }
        drawnRoutePath = direction.path
        routeStart = direction.start
        routeEnd = direction.end
        drawnRouteColor = selectedRoute?.color ?? .accentColor
        routeDrawKey = "\(selectedRoute?.id ?? "")-\(direction.id)"
    }

    /// Frames the camera on the currently selected direction's path (falling back
    /// to its stop coordinates if the shape is unavailable), offset so the route
    /// sits in the map area VISIBLE above the sheet at the current detent — not
    /// centered behind it. Driven by `selectedDirectionId` (initial load + Picker
    /// changes). Reads `sheetModel.selectedDetent` here (a method, not `body`).
    private func frameSelectedDirection() {
        guard let direction = routeDetail.selectedDirection else { return }
        let coords = direction.path.isEmpty
            ? direction.stops.compactMap { $0.location?.toCLCoordinate() }
            : direction.path
        guard let region = MKCoordinateRegion(enclosing: coords) else { return }

        // Fit the route into the visible fraction above the sheet: inflate the
        // span so the route occupies only that fraction, then shift the center
        // south (lower latitude) by the added height so it sits in the top part.
        let fraction = visibleFraction(for: sheetModel.selectedDetent)
        let latDelta = region.span.latitudeDelta / fraction
        let addedLat = latDelta - region.span.latitudeDelta
        let framed = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.center.latitude - addedLat / 2,
                longitude: region.center.longitude
            ),
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: region.span.longitudeDelta)
        )
        withAnimation { camera = .region(framed) }
    }

    /// Approximate fraction of the map height left visible above the sheet at a
    /// given detent. Peek leaves almost all of it; medium ~the top half.
    private func visibleFraction(for detent: PresentationDetent) -> CGFloat {
        detent == .medium ? 0.5 : 0.85
    }

    // MARK: - Helpers

    /// Refreshes `displayedStops` for a settled camera region, but skips work
    /// when nothing meaningful changed — specifically when only the map inset
    /// shifted (detent change), which fires `onMapCameraChange` with an
    /// essentially unchanged region. That skip is what removes the detent hitch.
    private func updateDisplayedStops(for region: MKCoordinateRegion) {
        // Zoomed out past the threshold: too dense to draw/read — show none.
        guard region.span.latitudeDelta <= Self.markerThreshold else {
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

    /// Stops within the visible region's bounding box. No cap or ranking — this
    /// is only called when zoomed in past `markerThreshold`, which bounds the
    /// count, and membership depends only on the region (not a center-relative
    /// ranking), so markers stay stable while panning.
    private func stopsInRegion(_ region: MKCoordinateRegion) -> [Foli.Stop] {
        let latRange = (region.center.latitude - region.span.latitudeDelta / 2)
            ... (region.center.latitude + region.span.latitudeDelta / 2)
        let lonRange = (region.center.longitude - region.span.longitudeDelta / 2)
            ... (region.center.longitude + region.span.longitudeDelta / 2)
        return allStops.within(latRange: latRange, lonRange: lonRange)
    }

    /// Center the camera on the user's location once it's available.
    ///
    /// `LocationManager.currentLocation` is `@ObservationIgnored` and populates
    /// asynchronously after authorization, so it may still be `nil` on first
    /// appear. We poll briefly for it rather than reading once. This only sets
    /// the *initial* camera — the map doesn't live-recenter as the user moves.
    private func centerOnUser() async {
        guard locationManager.checkLocationAuthorization() else { return }
        for _ in 0..<20 {
            if let coordinate = locationManager.currentLocation {
                withAnimation {
                    camera = .region(MKCoordinateRegion(center: coordinate, span: Self.defaultSpan))
                }
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

    /// Whether two regions are close enough to treat as the same view — used to
    /// skip marker recomputes triggered by inset changes rather than real pans.
    /// Epsilon is a fraction of the current span, so it scales with zoom.
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
