//
//  RouteDetailStore.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import Observation
import FoliBusUI
import PosankkaCore

/// The selected route's directions and which one is shown; the map and the
/// card's list both follow `selectedDirectionId`.
@MainActor
@Observable
final class RouteDetailStore {
    private let client: FoliClient
    /// Replaced per route, so a new route starts at `.loading`.
    private(set) var directions = ResourceStore<[RouteDirection]>()
    var selectedDirectionId: Int?

    init(client: FoliClient) {
        self.client = client
    }

    var allDirections: [RouteDirection] { directions.state.value ?? [] }
    var selectedDirection: RouteDirection? {
        allDirections.first { $0.id == selectedDirectionId }
    }

    /// Loads directions and selects the first.
    func load(routeId: String) async {
        selectedDirectionId = nil
        let store = ResourceStore<[RouteDirection]>()
        directions = store
        let client = client
        await store.load { try await RouteDirection.load(routeId: routeId, client: client) }
        // Superseded by another load or a reset: don't resurrect a closed route.
        guard !Task.isCancelled, directions === store else { return }
        selectedDirectionId = allDirections.first?.id
    }

    /// Clears the route; an in-flight load sees the new store and bails.
    func reset() {
        selectedDirectionId = nil
        directions = ResourceStore<[RouteDirection]>()
    }
}
