//
//  AppModel.swift
//  PosankkaMatka
//

import Foundation
import Observation
import FoliBusUI
import PosankkaCore

/// App-wide state: the shared data stores, the card selection, and the
/// loading and polling that follow from it. Map framing stays in `HomeView`.
@MainActor
@Observable
final class AppModel {
    let client: FoliClient
    let location = LocationManager()
    let stops = ResourceStore<[Foli.Stop]>()
    let routes = ResourceStore<[Foli.Route]>()
    let routeDetail: RouteDetailStore
    let vehicles: VehicleStore

    private(set) var selection = Selection()
    /// Stops served by a ferry route; drawn with a ferry glyph.
    private(set) var boatStopIDs: Set<Foli.Stop.ID> = []

    @ObservationIgnored private var routeLoadTask: Task<Void, Never>?

    init(client: FoliClient) {
        self.client = client
        routeDetail = RouteDetailStore(client: client)
        vehicles = VehicleStore(client: client)
    }

    var allStops: [Foli.Stop] { stops.state.value ?? [] }

    func loadStopsAndRoutes() async {
        let client = client
        async let loadedStops: Void = stops.load { try await client.fetchStops() }
        async let loadedRoutes: Void = routes.load { try await client.fetchRoutes() }
        _ = await (loadedStops, loadedRoutes)
    }

    func loadBoatStops() async {
        guard let routes = routes.state.value else { return }
        boatStopIDs = await client.ferryStopIDs(in: routes)
    }

    func stop(withID id: Foli.Stop.ID) -> Foli.Stop? {
        allStops.first { $0.id == id }
    }

    // MARK: - Selection

    /// Opens or swaps the stop card, over the route card if one is up.
    func selectStop(_ stop: Foli.Stop) {
        selection.stop = stop
        updateVehicleMonitoring()
    }

    /// Opens the route card and loads its directions; `onLoaded` runs only if
    /// the route is still selected when they arrive.
    func selectRoute(_ route: Foli.Route, onLoaded: @escaping @MainActor () -> Void) {
        guard route != selection.route else { return }
        selection = Selection(route: route)
        routeLoadTask?.cancel()
        routeLoadTask = Task {
            await routeDetail.load(routeId: route.id)
            guard !Task.isCancelled else { return }
            onLoaded()
        }
        updateVehicleMonitoring()
    }

    /// Pops the stop card: back to the route under it, else to the lists.
    func closeStop() {
        guard selection.stop != nil else { return }
        selection.stop = nil
        updateVehicleMonitoring()
    }

    /// Closes the card entirely, back to the lists.
    func closeCard() {
        guard !selection.isEmpty else { return }
        selection = Selection()
        routeLoadTask?.cancel()
        routeLoadTask = nil
        routeDetail.reset()
        updateVehicleMonitoring()
    }

    /// Polls vehicles for the open card (stop scope wins); none when closed.
    private func updateVehicleMonitoring() {
        if let stop = selection.stop {
            vehicles.start(.stop(stop.id))
        } else if let route = selection.route {
            vehicles.start(.line(route.shortName))
        } else {
            vehicles.stopMonitoring()
        }
    }
}
