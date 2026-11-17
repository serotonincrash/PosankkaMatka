//
//  RouteDetailList.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import FoliBusUI
import PosankkaCore

/// The pushed route detail: a direction Picker above that direction's stops.
struct RouteDetailList: View {
    let route: Foli.Route
    @Binding var selectedStopID: Foli.Stop.ID?
    @Environment(AppModel.self) private var model
    private var routeDetail: RouteDetailStore { model.routeDetail }
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Moves VoiceOver focus past the grabber.
    @AccessibilityFocusState private var focusSubtitle: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Subtitle: the full name truncates as a large title.
            if !route.longName.isEmpty {
                Text(route.longName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, routeDetail.allDirections.count > 1 ? 4 : 8)
                    // Focus lands here; the corridor name alone doesn't say which route.
                    .accessibilityLabel(route.spokenDescription)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($focusSubtitle)
            }
            if routeDetail.allDirections.count > 1 {
                directionPicker
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            content
        }
        // Inline: the card's bar keeps one display mode across content swaps.
        .navigationTitle("Route \(route.shortName)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focusSubtitle = true }
    }

    /// Menu at accessibility sizes; segments clip long headsigns.
    @ViewBuilder
    private var directionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            directionPickerBody(.menu)
        } else {
            directionPickerBody(.segmented)
        }
    }

    /// Segmented style drops the title from VoiceOver, so label it explicitly.
    private func directionPickerBody(_ style: some PickerStyle) -> some View {
        @Bindable var routeDetail = routeDetail
        return Picker("Direction", selection: $routeDetail.selectedDirectionId) {
            ForEach(routeDetail.allDirections) { direction in
                Text(direction.headsign).tag(Optional(direction.id))
            }
        }
        .pickerStyle(style)
        .accessibilityLabel("Direction")
        .accessibilityHint("Switches which direction's stops are shown")
    }

    @ViewBuilder
    private var content: some View {
        switch routeDetail.directions.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .success:
            // No directions means no trips; empty stops means stop times don't resolve.
            if routeDetail.allDirections.isEmpty {
                ContentUnavailableView("Not Running", systemImage: "bus",
                                       description: Text("This route has no trips in the current service period."))
            } else if let direction = routeDetail.selectedDirection, !direction.stops.isEmpty {
                List {
                    Section {
                        ForEach(direction.stops) { stop in
                            Button {
                                selectedStopID = stop.id
                            } label: {
                                StopRowLabel(stopID: stop.id, name: stop.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .tint(.primary)
                            .accessibilityLabel(StopWithDistance(stop).spokenDescription)
                            .accessibilityHint("Opens live arrivals for this stop")
                            .stopInputLabels(stopID: stop.id, name: stop.name)
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
