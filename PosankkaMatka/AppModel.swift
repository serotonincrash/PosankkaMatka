//
//  AppModel.swift
//  PosankkaMatka
//

import Foundation
import Observation
import FoliBusUI
import PosankkaCore

/// Shared stores, the card selection and its loading/polling. Map framing lives in `HomeView`.
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

    /// SIRI `lineRef` is the route's short name, not its id.
    func route(forLine lineRef: String) -> Foli.Route? {
        routes.state.value?.first { $0.shortName == lineRef }
    }

    // MARK: - Selection

    /// Pushes a stop card; swaps the top one if it is already a stop.
    func selectStop(_ stop: Foli.Stop) {
        selection.pushReplacingSameKind(.stop(stop))
        selectionDidChange()
    }

    /// Pushes a vehicle card; swaps the top one if it is already a vehicle.
    func selectVehicle(_ key: TripKey) {
        selection.pushReplacingSameKind(.vehicle(key))
        selectionDidChange()
    }

    /// Starts a fresh stack on the route and loads its directions; `onLoaded`
    /// runs only if the route is still selected when they arrive.
    func selectRoute(_ route: Foli.Route, onLoaded: @escaping @MainActor () -> Void) {
        guard selection.cards != [.route(route)] else { return }
        selection.openRoute(route)
        routeLoadTask?.cancel()
        routeLoadTask = Task {
            await routeDetail.load(routeId: route.id)
            guard !Task.isCancelled else { return }
            onLoaded()
        }
        selectionDidChange()
    }

    /// Pops the top card, revealing the one under it or the lists.
    func closeTop() {
        guard !selection.isEmpty else { return }
        selection.pop()
        selectionDidChange()
    }

    /// Closes every card, back to the lists.
    func closeAll() {
        guard !selection.isEmpty else { return }
        selection.popAll()
        selectionDidChange()
    }

    private func selectionDidChange() {
        if selection.route == nil, routeLoadTask != nil {
            routeLoadTask?.cancel()
            routeLoadTask = nil
            routeDetail.reset()
        }
        updateVehicleMonitoring()
    }

    /// Polls for the topmost stop or route card; none when closed.
    private func updateVehicleMonitoring() {
        // PHASE2: a vehicle on top should use `.trip(key)` once VehicleTracker
        // has it; until then it keeps the scope of the card it was opened from.
        for card in selection.cards.reversed() {
            switch card {
            case .stop(let stop):
                vehicles.start(.stop(stop.id))
                return
            case .route(let route):
                vehicles.start(.line(route.shortName))
                return
            case .vehicle:
                continue
            }
        }
        if let key = selection.vehicle {
            vehicles.start(.line(key.lineRef))
        } else {
            vehicles.stopMonitoring()
        }
    }
}
