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
    /// Steers VoiceOver past the sheet's grabber on appear.
    @AccessibilityFocusState private var focusSubtitle: Bool

    var body: some View {
        @Bindable var routeDetail = routeDetail

        VStack(spacing: 0) {
            // The corridor name as a quiet subtitle — the full name truncates
            // as a large title.
            if !route.longName.isEmpty {
                Text(route.longName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, routeDetail.allDirections.count > 1 ? 4 : 8)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusSubtitle)
            }
            // Pinned above the list so it stays visible while the stops scroll.
            if routeDetail.allDirections.count > 1 {
                Picker("Direction", selection: $routeDetail.selectedDirectionId) {
                    ForEach(routeDetail.allDirections) { direction in
                        Text(direction.headsign).tag(Optional(direction.id))
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .accessibilityHint("Switches which direction's stops are shown")
            }

            content
        }
        // "Route N"; inline like the stop title — the card's bar keeps one
        // display mode across content swaps.
        .navigationTitle("Route \(route.shortName)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusSubtitle = true }
    }

    @ViewBuilder
    private var content: some View {
        switch routeDetail.directions.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .success:
            // Empty directions ⇔ no trips; a direction with empty stops means
            // trips exist but their stop times don't resolve.
            if routeDetail.allDirections.isEmpty {
                ContentUnavailableView("Not Running", systemImage: "bus",
                                       description: Text("This route has no trips in the current service period."))
            } else if let direction = routeDetail.selectedDirection, !direction.stops.isEmpty {
                // No section header — the direction is already shown by the
                // picker (or the single-direction subtitle) above.
                List {
                    Section {
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
                            // Same phrasing as the master list's stop rows;
                            // Voice Control gets the short forms.
                            .accessibilityLabel(StopWithDistance(stop).spokenDescription)
                            .accessibilityHint("Shows live arrivals for this stop")
                            .accessibilityInputLabels([
                                "\(stop.id) \(stop.name)",
                                stop.name
                            ])
                        }
                    } footer: {
                        Text("Live stop and bus data refreshes periodically and may not always be accurate.")
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
