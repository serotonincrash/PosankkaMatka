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

    @State private var locationManager = LocationManager()
    @State private var stopsStore = ResourceStore<[Foli.Stop]>()
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
    /// The sheet's current detent. Starts at `.medium` (so the list is visible
    /// on launch) and is bound so tapping a marker can raise it to `.medium`,
    /// keeping `StopView` visible rather than obscured at the peek.
    @State private var selectedDetent: PresentationDetent = .medium

    @State private var stop: StopWithDistance?

    var body: some View {
        TabView {
            Tab("Stops", systemImage: "house.and.flag") {
                Map(position: $camera, selection: $selectedStopID) {
                    UserAnnotation()
                    mapContent
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    visibleRegion = context.region
                    updateDisplayedStops(for: context.region)
                }
                .onChange(of: selectedStopID) { _, newValue in
                    handleSelection(newValue)
                }
                .onChange(of: stop) { _, newStop in
                    // Returned to the list: drop the marker highlight so the same
                    // stop is re-tappable.
                    if newStop == nil { selectedStopID = nil }
                }
                .sheet(isPresented: .constant(true)) {
                    NavigationStack {
                        ListStopsView(selectedStopID: $selectedStopID)
                            // No `.large` detent: at full coverage iOS dims the
                            // presenter regardless of the undimmed boundary, and that
                            // dim layer hitches the live Map. Capping at `.medium`
                            // avoids it; the list is fully usable at that height.
                            // Background interaction stays enabled (keeps the map
                            // tappable and undimmed) at both remaining detents.
                            .presentationDetents([.height(110), .medium], selection: $selectedDetent)
                            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                            .interactiveDismissDisabled()
                        .navigationDestination(item: $stop) { stop in
                            StopView(stopWithDistance: stop)
                                // New stop id → fresh StopView identity → its
                                // @State store resets and re-fetches arrivals,
                                // rather than reusing the previous stop's data.
                                .id(stop.id)
                        }
                    }
                }
            }
            Tab("Routes", systemImage: "map") {
                RouteView()
            }
        }
        .environment(locationManager)
        .environment(stopsStore)
        .task {
            let foli = foli
            await stopsStore.load { try await foli.fetchStops() }
            await centerOnUser()
        }
    }

    // MARK: - Map content

    private var allStops: [Foli.Stop] {
        stopsStore.state.value ?? []
    }

    /// Renders the precomputed `displayedStops`. The set is maintained in
    /// `updateDisplayedStops(for:)`, so a `body` re-eval from an inset/detent
    /// change reuses the same array (stable identities → no marker rebuild).
    @MapContentBuilder
    private var mapContent: some MapContent {
        ForEach(displayedStops) { stop in
            if let coordinate = stop.location?.toCLCoordinate() {
                Marker(stop.name, coordinate: coordinate)
                    .tag(stop.id)
            }
        }
    }

    // MARK: - Selection

    /// Tapping a stop opens its `StopView`, keeps the marker highlighted,
    /// recenters the map on it (keeping the current zoom), and raises the sheet
    /// to `.medium` so the detail isn't obscured at the peek. The target is
    /// nudged south so the stop lands in the visible strip above the sheet — the
    /// map carries no sheet inset (that caused a detent hitch), so we offset only
    /// here, once. `selectedStopID` is *not* cleared here (that would drop the
    /// highlight); it's cleared in `onChange(of: stop)` when the user returns.
    private func handleSelection(_ newValue: Foli.Stop.ID?) {
        guard let newValue,
              let found = allStops.first(where: { $0.id == newValue }),
              let coordinate = found.location?.toCLCoordinate() else { return }
        let span = visibleRegion?.span ?? Self.defaultSpan
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
        withAnimation {
            selectedDetent = .medium
        }
        stop = StopWithDistance(found)
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
