//
//  VehicleCardView.swift
//  PosankkaMatka
//

import SwiftUI
import FoliBusUI
import PosankkaCore

/// Placeholder vehicle card. PHASE2: replace with the live stop rail.
struct VehicleCardView: View {
    let key: TripKey
    @Environment(AppModel.self) private var model

    /// Nil once the bus leaves the polled scope.
    private var vehicle: Foli.VehicleLocation? {
        model.vehicles.displayVehicles(at: .now).first { $0.id == key.vehicleRef }?.vehicle
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    if let route = model.route(forLine: key.lineRef) {
                        RouteBadge(route: route)
                    }
                    VStack(alignment: .leading) {
                        if let destination = vehicle?.destinationName {
                            Text(destination).font(.headline)
                        }
                        if let next = vehicle?.nextStopPointName {
                            Text("Next: \(next)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Bus \(key.lineRef)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
