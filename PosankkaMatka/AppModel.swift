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
    let stopAlert: StopAlertManager

    private(set) var selection = Selection()
    /// Stops served by a ferry route; drawn with a ferry glyph.
    private(set) var boatStopIDs: Set<Foli.Stop.ID> = []

    /// Directions per route id, for matching a tracked bus to its trip shape.
    private(set) var directionsByRoute: [String: [RouteDirection]] = [:]

    @ObservationIgnored private var routeLoadTask: Task<Void, Never>?
    @ObservationIgnored private var directionLoads: Set<String> = []
    /// Exact trips per GTFS trip id; preferred over matching a line direction.
    private var tripDirections: [String: RouteDirection] = [:]
    @ObservationIgnored private var tripLoads: Set<String> = []
    @ObservationIgnored private var stopIndex: (count: Int, byID: [Foli.Stop.ID: Foli.Stop]) = (0, [:])
    @ObservationIgnored private var routeIndex: (count: Int, byLine: [String: Foli.Route]) = (0, [:])

    init(client: FoliClient) {
        self.client = client
        routeDetail = RouteDetailStore(client: client)
        vehicles = VehicleStore(client: client)
        stopAlert = StopAlertManager(client: client)
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
        stopsByID[id]
    }

    func route(forLine lineRef: String) -> Foli.Route? {
        routesByLine[lineRef]
    }

    /// Routes by SIRI `lineRef`, which is the short name, not the route id.
    /// Rebuilt only when the route list changes size; read per map tick.
    var routesByLine: [String: Foli.Route] {
        let routes = routes.state.value ?? []
        if routeIndex.count != routes.count {
            routeIndex = (routes.count, Dictionary(routes.map { ($0.shortName, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        return routeIndex.byLine
    }

    /// Rebuilt only when the stop list changes size; journeys look stops up per frame.
    private var stopsByID: [Foli.Stop.ID: Foli.Stop] {
        let stops = allStops
        if stopIndex.count != stops.count {
            stopIndex = (stops.count, Dictionary(stops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }))
        }
        return stopIndex.byID
    }

    // MARK: - Tracked vehicle

    /// The vehicle card's trip status; nil unless a vehicle card is on top.
    func tripStatus(at date: Date) -> VehicleTracker.TripStatus? {
        guard selection.vehicle != nil else { return nil }
        return vehicles.tripStatus(at: date)
    }

    /// The top vehicle card's rail, from its live or held position. Nil while
    /// pending or once the trip has ended or been lost.
    func journey(at date: Date) -> (journey: VehicleJourney, position: VehicleTracker.Position, lastSeen: Date?)? {
        let position: VehicleTracker.Position
        let lastSeen: Date?
        switch tripStatus(at: date) {
        case .live(let p): position = p; lastSeen = nil
        case .stale(let p, let seen): position = p; lastSeen = seen
        default: return nil
        }
        let journey = VehicleJourney(
            vehicle: position.vehicle,
            direction: direction(for: position.vehicle),
            stops: stopsByID
        )
        return (journey, position, lastSeen)
    }

    /// The bus's exact GTFS trip once loaded, else the line direction its
    /// upcoming stops best match.
    private func direction(for vehicle: Foli.VehicleLocation) -> RouteDirection? {
        if let tripId = vehicle.gtfsTripId {
            if let exact = tripDirections[tripId] { return exact }
            loadTrip(tripId)
        }
        let directions = route(forLine: vehicle.lineRef).flatMap { directionsByRoute[$0.id] } ?? []
        return directions.bestMatch(for: vehicle)
    }

    /// Loads (once) one trip's stops and shape. Safe to call during a view
    /// update: observable state only changes when the load finishes.
    private func loadTrip(_ tripId: String) {
        guard tripDirections[tripId] == nil, tripLoads.insert(tripId).inserted else { return }
        let client = client
        Task {
            let loaded = try? await RouteDirection.load(tripId: tripId, client: client)
            if let loaded {
                tripDirections[tripId] = loaded
                tripLoads.remove(tripId)
            }
            // A failed load stays in `tripLoads`, so it isn't retried every frame.
        }
    }

    /// Loads (once) the directions of the line a tracked bus runs on.
    private func loadDirections(forLine lineRef: String) {
        guard let route = route(forLine: lineRef),
              directionsByRoute[route.id] == nil,
              directionLoads.insert(route.id).inserted else { return }
        let client = client
        Task {
            let loaded = try? await RouteDirection.load(routeId: route.id, client: client)
            directionLoads.remove(route.id)
            if let loaded { directionsByRoute[route.id] = loaded }
        }
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

    /// Polls for the top card: a vehicle tracks just its trip; none when closed.
    private func updateVehicleMonitoring() {
        switch selection.top {
        case .stop(let stop):
            vehicles.start(.stop(stop.id))
        case .route(let route):
            vehicles.start(.line(route.shortName))
        case .vehicle(let key):
            vehicles.start(.trip(key))
            // The line's directions are the fallback when the exact trip is unknown or fails.
            loadDirections(forLine: key.lineRef)
            if let tripId = vehicles.latestVehicles.first(where: { $0.vehicleRef == key.vehicleRef })?.gtfsTripId {
                loadTrip(tripId)
            }
        case nil:
            vehicles.stopMonitoring()
        }
    }
}
