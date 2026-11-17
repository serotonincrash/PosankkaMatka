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
    /// The camera tracks the vehicle card's bus until the user moves the map.
    @State private var isFollowing = false
    /// Per-tick follow bookkeeping; a plain class so writes don't re-render.
    @State private var follow = FollowState()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Sheets are siblings of the map so detent drags don't re-render it.
        ZStack {
            // Ticks only the map, for interpolated vehicle positions.
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let tracked = model.journey(at: context.date)
                let vehicleOnTop = model.selection.vehicle != nil
                MapView(
                    camera: $camera,
                    selection: mapSelection,
                    mapScope: mapScope,
                    displayedStops: displayedStops,
                    boatStopIDs: model.boatStopIDs,
                    direction: vehicleOnTop ? nil : model.routeDetail.selectedDirection,
                    routeColor: model.selection.route?.color ?? .accentColor,
                    isZoomedIn: isZoomedIn,
                    hidesViewportStops: model.selection.route != nil || vehicleOnTop,
                    journey: tracked.map(journeyOverlay),
                    vehicles: model.vehicles.displayVehicles(at: context.date),
                    lineRoutes: lineRoutes,
                    selectedVehicleRef: model.selection.vehicle?.vehicleRef
                )
                .ignoresSafeArea(edges: .bottom)
                // Everything on the map is reachable through the sheets.
                .accessibilityHidden(true)
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    liveCamera = context.camera
                    updateDisplayedStops(for: context.region)
                }
                .onChange(of: context.date) {
                    followTick(tracked?.position.coordinate.toCLCoordinate())
                }
            }
            .onChange(of: scenePhase) { _, phase in
                model.vehicles.isPaused = phase != .active
            }
            .onChange(of: camera.positionedByUser) { _, byUser in
                if byUser { isFollowing = false }
            }
            .onChange(of: model.selection.vehicle) { _, key in
                vehicleCardChanged(to: key)
            }

            VStack(spacing: 12) {
                Group {
                    MapLocateButton(isAuthorized: model.location.isAuthorized, action: recenterOnUser)
                    MapCompass(scope: mapScope)
                }
                .accessibilityHidden(true)
                if model.selection.vehicle != nil {
                    FollowBusButton(isFollowing: isFollowing, action: resumeFollowing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, 16)

            SheetHost(
                selection: model.selection,
                selectedStopID: stopSelection,
                selectedRoute: routeSelection,
                sheetModel: sheetModel,
                onClose: model.closeTop,
                onCloseAll: model.closeAll,
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

    private func journeyOverlay(
        _ tracked: (journey: VehicleJourney, position: VehicleTracker.Position, lastSeen: Date?)
    ) -> JourneyOverlay {
        let split = tracked.journey.splitPath(at: tracked.position.coordinate)
        return JourneyOverlay(
            travelled: split.travelled,
            remaining: split.remaining,
            calls: tracked.journey.calls,
            color: model.route(forLine: tracked.journey.trip.lineRef)?.color ?? .accentColor
        )
    }

    // MARK: - Follow camera

    /// Street-level distance (m) for a bus framed from further out.
    private static let followDistance: Double = 2_500

    private func vehicleCardChanged(to key: TripKey?) {
        guard key != nil else {
            isFollowing = false
            return
        }
        // Opened from a puck or a stop card's arrival: either way at .medium.
        if sheetModel.cardDetent != .medium {
            sheetModel.suppressDetentReframe = true
            sheetModel.cardDetent = .medium
        }
        isFollowing = true
        follow.distance = min(liveCamera?.distance ?? Self.followDistance, Self.followDistance)
        follow.needsFraming = true
        followTick(model.journey(at: .now)?.position.coordinate.toCLCoordinate())
    }

    private func followTick(_ coordinate: CLLocationCoordinate2D?) {
        guard let coordinate else { return }
        follow.lastCoordinate = coordinate
        guard isFollowing else { return }
        let nudge = (1 - visibleFraction(for: sheetModel.cardDetent)) / 2
        if follow.needsFraming {
            follow.needsFraming = false
            moveCamera(anchor: coordinate, nudge: nudge, distance: follow.distance,
                       animation: .easeInOut(duration: 0.4))
        } else {
            // Linear over one tick, so per-tick moves join into one glide.
            moveCamera(anchor: coordinate, nudge: nudge, distance: follow.distance,
                       animation: .linear(duration: 0.5))
        }
    }

    private func resumeFollowing() {
        isFollowing = true
        follow.distance = liveCamera?.distance ?? Self.followDistance
        follow.needsFraming = true
        followTick(follow.lastCoordinate)
    }

    // MARK: - Selection

    /// MapKit sets nil when empty map or the selected item is tapped, which
    /// pops a stop or vehicle card (not a route: that needs the X).
    private var mapSelection: Binding<MapItem?> {
        Binding(
            get: {
                switch model.selection.top {
                case .stop(let stop): .stop(stop.id)
                case .vehicle(let key): .vehicle(key.vehicleRef)
                case .route, nil: nil
                }
            },
            set: { item in
                switch item {
                case .stop(let id): selectStop(id: id)
                case .vehicle(let ref): selectVehicle(ref: ref)
                case nil: popTappedAwayCard()
                }
            }
        )
    }

    /// For the lists and route card, which only ever set a stop.
    private var stopSelection: Binding<Foli.Stop.ID?> {
        Binding(
            get: { model.selection.stop?.id },
            set: { id in
                if let id { selectStop(id: id) } else { popTappedAwayCard() }
            }
        )
    }

    private var routeSelection: Binding<Foli.Route?> {
        Binding(
            get: { model.selection.route },
            set: { route in
                if let route { selectRoute(route) } else { model.closeAll() }
            }
        )
    }

    private func popTappedAwayCard() {
        switch model.selection.top {
        case .stop, .vehicle: model.closeTop()
        case .route, nil: break
        }
    }

    private func selectVehicle(ref: String) {
        guard ref != model.selection.vehicle?.vehicleRef,
              let vehicle = model.vehicles.displayVehicles(at: .now).first(where: { $0.id == ref })?.vehicle
        else { return }
        // Detent and follow camera are set up in `vehicleCardChanged`.
        model.selectVehicle(TripKey(vehicle))
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
    /// `distance` overrides the live zoom.
    private func moveCamera(
        anchor: CLLocationCoordinate2D,
        nudge: CGFloat,
        distance: Double? = nil,
        animation: Animation = .default
    ) {
        guard let cam = liveCamera else { return }
        let distance = distance ?? cam.distance
        let heading = cam.heading * .pi / 180
        // Longitude degrees shrink with latitude.
        let scale = max(cos(anchor.latitude * .pi / 180), 0.2)
        // Bounding span = width·|sin h| + height·|cos h|; recover the height
        // assuming a portrait phone's ~2:1 aspect. The span scales with distance.
        let bbox = (visibleRegion?.span.latitudeDelta ?? Self.defaultSpan.latitudeDelta) * distance / cam.distance
        let height = bbox / (abs(cos(heading)) + abs(sin(heading)) / 2)
        let (upEast, upNorth) = (sin(heading), cos(heading))
        let center = CLLocationCoordinate2D(
            latitude: anchor.latitude - nudge * height * upNorth,
            longitude: anchor.longitude - nudge * height * upEast / scale
        )
        withAnimation(reduceMotion ? nil : animation) {
            camera = .camera(MapCamera(
                centerCoordinate: center,
                distance: distance,
                heading: cam.heading,
                pitch: cam.pitch
            ))
        }
    }

    /// Re-seats the top card's subject above a user-dragged card.
    private func reframeSelection() {
        let anchor: CLLocationCoordinate2D
        switch model.selection.top {
        case .stop(let stop):
            guard let coordinate = stop.location?.toCLCoordinate() else { return }
            anchor = coordinate
        case .route:
            guard let direction = model.routeDetail.selectedDirection,
                  let center = MKCoordinateRegion(
                      enclosing: direction.framingCoordinates.map { $0.toCLCoordinate() }
                  )?.center
            else { return }
            anchor = center
        case .vehicle:
            // Re-seat the followed bus for the new inset; unfollowed, leave the map alone.
            guard isFollowing, let coordinate = follow.lastCoordinate else { return }
            anchor = coordinate
        case nil:
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
        guard case .route = model.selection.top,
              let direction = model.routeDetail.selectedDirection else { return }
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
        isFollowing = false
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

private final class FollowState {
    var lastCoordinate: CLLocationCoordinate2D?
    var distance: Double = 2_500
    /// The next tick frames (zooms) rather than glides.
    var needsFraming = false
}

/// Resumes following the vehicle card's bus after the user moved the map.
private struct FollowBusButton: View {
    let isFollowing: Bool
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 44

    private var label: some View {
        Image(systemName: isFollowing ? "scope" : "location.viewfinder")
            .font(.body.weight(.semibold))
            .foregroundStyle(isFollowing ? Color.accentColor : Color.primary)
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
        .accessibilityLabel("Follow Bus")
        .accessibilityHint(isFollowing ? "" : "Keeps the map centered on the bus")
        .accessibilityAddTraits(isFollowing ? .isSelected : [])
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
