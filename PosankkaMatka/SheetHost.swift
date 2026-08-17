//
//  SheetHost.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import Observation
import FoliBusUI

/// Shared sheet detent, owned by `HomeView`. Only `SheetHost` binds it and only
/// framing methods read it — `body` must not, or per-drag-frame writes re-subscribe
/// and bring back the detent hitch.
@MainActor
@Observable
final class SheetModel {
    var selectedDetent: PresentationDetent = .medium
}

/// Hosts the persistent home sheet in isolation from the map, so sheet-drag detent
/// writes invalidate only this trivial view — not `HomeView`, which renders the
/// live map. The map (a ZStack sibling) stays undimmed behind the sheet via
/// host-wide `presentationBackgroundInteraction`.
struct SheetHost: View {
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?
    @Binding var stop: StopWithDistance?
    /// Whether a detail is shown; drives the detent raise.
    let showingDetail: Bool
    /// Shared detent state, bound to the sheet.
    @Bindable var sheetModel: SheetModel

    var body: some View {
        Color.clear
            .allowsHitTesting(false)   // never intercept taps meant for the map
            .sheet(isPresented: .constant(true)) {
                NavigationStack {
                    ListStopsView(selectedStopID: $selectedStopID, selectedRoute: $selectedRoute)
                        .presentationDetents([.height(110), .medium], selection: $sheetModel.selectedDetent)
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                        .interactiveDismissDisabled()
                        .navigationDestination(item: $stop) { stop in
                            StopView(stopWithDistance: stop)
                                // Fresh identity per stop → its store resets and
                                // re-fetches arrivals rather than reusing stale data.
                                .id(stop.id)
                        }
                        .navigationDestination(item: $selectedRoute) { route in
                            RouteDetailList(route: route, selectedStopID: $selectedStopID)
                        }
                }
            }
            // Detent follows navigation depth (Maps-style): raise peek → medium
            // when a detail appears, only if currently at peek; never auto-drop on
            // return, so the user's manual detent is respected.
            .onChange(of: showingDetail) { _, isShowing in
                if isShowing, sheetModel.selectedDetent == .height(110) {
                    withAnimation { sheetModel.selectedDetent = .medium }
                }
            }
    }
}
