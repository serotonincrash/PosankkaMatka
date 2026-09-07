//
//  RouteDetailList.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import FoliBusUI

/// The pushed route detail: a direction Picker above the selected direction's
/// stops. `RouteDetailStore` is the shared source of truth, so the Picker drives
/// the map and this list together.
struct RouteDetailList: View {
    let route: Foli.Route
    @Binding var selectedStopID: Foli.Stop.ID?
    @Environment(RouteDetailStore.self) private var routeDetail

    var body: some View {
        @Bindable var routeDetail = routeDetail

        VStack(spacing: 0) {
            // Pinned above the list so it stays visible while the stops scroll.
            if routeDetail.allDirections.count > 1 {
                Picker("Direction", selection: $routeDetail.selectedDirectionId) {
                    ForEach(routeDetail.allDirections) { direction in
                        Text(direction.headsign).tag(Optional(direction.id))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            content
        }
        .navigationTitle(route.fullDisplayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var content: some View {
        switch routeDetail.directions.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .success:
            // Empty directions ⇔ no trips (rows come from trip groups); a row
            // with empty stops means trips exist but their stop times don't resolve.
            if routeDetail.allDirections.isEmpty {
                ContentUnavailableView("Not Running", systemImage: "bus",
                                       description: Text("This route has no trips in the current service period."))
            } else if let direction = routeDetail.selectedDirection, !direction.stops.isEmpty {
                List {
                    Section(direction.headsign) {
                        ForEach(direction.stops) { stop in
                            Button {
                                selectedStopID = stop.id
                            } label: {
                                HStack {
                                    Text(stop.id).monospaced()
                                    Text(stop.name)
                                    Spacer()
                                }
                            }
                            .tint(.primary)
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Stops", systemImage: "bus",
                                       description: Text("This route's trips have no stop information."))
            }
        case .failure(let error):
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
        }
    }
}
