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
    /// Initial span when centering on the user's location (~1.7 km tall).
    private static let defaultSpan = MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
    /// Span (degrees) at or below which markers show; further out, none.
    private static let markerThreshold: CLLocationDegrees = 0.06
    /// Street-level span for a stop selected while zoomed out.
    private static let selectionSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)

    @Environment(AppModel.self) private var model
    /// Associates the map with the scoped compass in the controls overlay;
    /// connected by `.mapScope` on the containing ZStack.
    @Namespace private var mapScope

    @State private var camera: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    /// Live camera from the last change (user or programmatic) — the zoom and
    /// orientation to preserve when reframing. `visibleRegion` alone can't:
    /// its span is the axis-aligned bounding box, inflated when rotated.
    @State private var liveCamera: MapCamera?
    /// Markers currently drawn; recomputed only on meaningful camera changes.
    @State private var displayedStops: [Foli.Stop] = []
    /// Region that produced `displayedStops`; skips no-op recomputes.
    @State private var lastMarkerRegion: MKCoordinateRegion?
    /// Shared sheet detents, bound only by `SheetHost`; this view reads them
    /// solely in untracked framing methods (see `onCardDetentChange`).
    @State private var sheetModel = SheetModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                // Out of the swipe chain: every map fact (stops, arrivals) is
                // reachable through the sheets, and with background
                // interaction on, map elements would trail the list's end.
                .accessibilityHidden(true)
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    liveCamera = context.camera
                    updateDisplayedStops(for: context.region)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Live data; don't burn it in the background.
                model.vehicles.isPaused = phase != .active
            }

            // Controls overlay, top-right: the scoped compass (bound to the
            // map by `.mapScope` below) stacks above the custom locate button
            // — custom because the native one centers the user at the map's
            // midpoint, behind the sheets, with no tap hook to reframe.
            VStack(spacing: 12) {
                MapLocateButton(isAuthorized: model.location.isAuthorized, action: recenterOnUser)
                MapCompass(scope: mapScope)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 16)
            // Manipulate the (a11y-hidden) map only — keep out of the chain.
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
            // Center once stops are in (markers for the first region need
            // them), without waiting on the slower ferry-stop lookup.
            async let centered: Void = centerOnUser()
            await model.loadBoatStops()
            await centered
        }
    }

    // MARK: - Map content

    /// The route per line number (SIRI `lineRef` == `route.shortName`, not the
    /// internal route id), for coloring live vehicle pins.
    private var lineRoutes: [String: Foli.Route] {
        Dictionary((model.routes.state.value ?? []).map { ($0.shortName, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    /// Derived from `visibleRegion` (not the camera binding) so it also tracks
    /// programmatic camera moves.
    private var isZoomedIn: Bool {
        guard let span = visibleRegion?.span.latitudeDelta else { return false }
        return span <= Self.markerThreshold
    }

    // MARK: - Selection

    /// The stop selection as the map and lists see it. Setting an ID opens
    /// (or swaps) the stop card; setting nil — MapKit does this when empty map
    /// or the selected marker is tapped — pops the stop card (Maps-style),
    /// back to the route if one is under it.
    private var stopSelection: Binding<Foli.Stop.ID?> {
        Binding(
            get: { model.selection.stop?.id },
            set: { id in
                if let id { selectStop(id: id) } else { model.closeStop() }
            }
        )
    }

    /// The route selection as the lists see it; nil closes the card.
    private var routeSelection: Binding<Foli.Route?> {
        Binding(
            get: { model.selection.route },
            set: { route in
                if let route { selectRoute(route) } else { model.closeCard() }
            }
        )
    }

    /// Presents (or swaps) the stop card and frames the stop above it.
    private func selectStop(id: Foli.Stop.ID) {
        guard id != model.selection.stop?.id,
              let found = model.stop(withID: id),
              let coordinate = found.location?.toCLCoordinate() else { return }
        // Every stop-card change re-opens at .medium — a tall or peek detent
        // carried over from the previous content buries the reframed map.
        // The reset must not ALSO fire the detent reframe: that handler runs
        // on stale camera state mid-swap and would clobber the framing issued
        // just below, so programmatic changes are flagged for the handler.
        if sheetModel.cardDetent != .medium {
            sheetModel.suppressDetentReframe = true
            sheetModel.cardDetent = .medium
        }
        // Recenter BEFORE presenting the card: the concurrent sheet transition
        // can make MapKit skip the camera animation and drop the zoom.
        frameSelectedStop(at: coordinate)
        model.selectStop(found)
    }

    /// Opens the route card at the default detent; frames the route once its
    /// directions load (Picker switches later just redraw the line/pins).
    private func selectRoute(_ route: Foli.Route) {
        sheetModel.cardDetent = .medium
        model.selectRoute(route, onLoaded: frameSelectedDirection)
    }

    /// Applies a selection/user framing: re-issues the live camera's zoom and
    /// orientation with only the center shifted along the screen axis, so
    /// rotated maps neither zoom-reset nor mis-seat above the sheet.
    private func moveCamera(anchor: CLLocationCoordinate2D, nudge: CGFloat) {
        guard let cam = liveCamera else { return }
        let heading = cam.heading * .pi / 180
            // Longitude degrees shrink by cos(latitude): converts the shift's
            // east component. Separately, the bounding span folds in the
            // viewport's *width* when rotated, so the true height needs the
            // height/width ratio to be recovered — hardcoded to a portrait
            // phone's ~2 (a home-button SE's ~1.73 is the worst case).
            let scale = max(cos(anchor.latitude * .pi / 180), 0.2)
            // Bounding latitude span = width·|sin h| + height·|cos h|.
            let bbox = visibleRegion?.span.latitudeDelta ?? Self.defaultSpan.latitudeDelta
            let height = bbox / (abs(cos(heading)) + abs(sin(heading)) / 2)
            // Screen-up unit vector in (east, north) components.
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

    /// Reframes the selection for a changed card detent (stop card wins).
    /// Only the center moves — zoom and orientation survive via `moveCamera`
    /// — re-seating the selection in the newly-sized visible strip. Fired by
    /// `SheetHost` from untracked context — never read from `body`.
    private func reframeSelection() {
        let anchor: CLLocationCoordinate2D
        if let coordinate = model.selection.stop?.location?.toCLCoordinate() {
            anchor = coordinate
        } else if let direction = model.routeDetail.selectedDirection {
            let coords = direction.path.isEmpty
                ? direction.stops.compactMap { $0.location?.toCLCoordinate() }
                : direction.path
            guard let center = MKCoordinateRegion(enclosing: coords)?.center else { return }
            anchor = center
        } else {
            return
        }
        // Shift the center south so the anchor sits above the card.
        let nudge = (1 - visibleFraction(for: sheetModel.cardDetent)) / 2
        moveCamera(anchor: anchor, nudge: nudge)
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
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            camera = .region(region)
        }
    }

    /// Frames the direction's path (or stop coords) above the route card —
    /// not centered behind it.
    private func frameSelectedDirection() {
        // The stop card wins: never re-frame the route over it.
        guard model.selection.stop == nil, let direction = model.routeDetail.selectedDirection else { return }
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
        withAnimation(reduceMotion ? nil : .default) { camera = .region(framed) }
    }

    /// Fraction of map height visible above the card. `.large` frames like
    /// medium: fitting into its sliver would zoom out ~4× and flatten turns.
    /// Peek's 0.85 is a cross-model approximation (110 pt covers 12–16% of
    /// the screen); it feeds a nudge heuristic, so the slop is imperceptible.
    private func visibleFraction(for detent: PresentationDetent) -> CGFloat {
        detent == SheetModel.peek ? 0.85 : 0.5
    }

    // MARK: - Helpers

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
        return model.allStops.within(latRange: latRange, lonRange: lonRange)
    }

    /// Centers on the user once a fix arrives (briefly polled; the map doesn't
    /// live-recenter).
    private func centerOnUser() async {
        guard model.location.isAuthorized else { return }
        for _ in 0..<20 {
            if let coordinate = model.location.currentLocation {
                // Shift south so the user sits above the sheet.
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
                return  // Task cancelled — stop polling.
            }
        }
    }

    /// The locate button's action: recenter on the user at the current zoom
    /// and orientation, framed above whatever sheet is up.
    private func recenterOnUser() {
        guard model.location.isAuthorized, let coordinate = model.location.currentLocation else { return }
        let detent = !model.selection.isEmpty ? sheetModel.cardDetent : sheetModel.listDetent
        moveCamera(anchor: coordinate, nudge: (1 - visibleFraction(for: detent)) / 2)
    }
}

/// Locate control: the native button centers the user at the map's midpoint,
/// behind the sheets, with no tap hook to reframe.
private struct MapLocateButton: View {
    let isAuthorized: Bool
    let action: () -> Void
    /// Tracks Dynamic Type so the target grows alongside giant text instead of
    /// pinning at the 44 pt floor.
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
        .environment(AppModel(client: DefaultFoliClientProvider().client()))
}
