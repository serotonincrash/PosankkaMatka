//
//  RouteDetailList.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import FoliBusUI

/// The pushed detail for a selected route: a direction Picker pinned above the
/// stops of the currently selected direction. The route's line and start/end
/// pins are drawn on the shared home map by `HomeView`; the shared
/// `RouteDetailStore` (loaded by HomeView) is the single source of truth, so the
/// Picker drives the map and this list together. Tapping a stop opens it.
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
            if let direction = routeDetail.selectedDirection {
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
                ContentUnavailableView("No Stops", systemImage: "bus", description: Text("This route has no stop information."))
            }
        case .failure(let error):
            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error.localizedDescription))
        }
    }
}
