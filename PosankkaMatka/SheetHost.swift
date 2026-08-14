//
//  SheetHost.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import Observation
import FoliBusUI

/// Shared sheet state. Holds `selectedDetent` so both `SheetHost` (which binds
/// the sheet's `selection:` to it) and `HomeView` (which reads it — in a method,
/// never in `body` — to frame routes above the sheet) see one source of truth.
///
/// Owned by `HomeView` as `@State`. IMPORTANT: `HomeView.body` must not read
/// `selectedDetent`, or it would re-subscribe to the per-drag-frame writes and
/// bring back the detent hitch. Only `SheetHost` binds it and only framing
/// methods read it (at call time, on discrete events).
@MainActor
@Observable
final class SheetModel {
    var selectedDetent: PresentationDetent = .medium
}

/// Hosts the persistent home sheet **in isolation from the map**. Owning
/// `selectedDetent` here (instead of on `HomeView`) means the continuous
/// `presentationDetents(selection:)` writes during a sheet drag invalidate only
/// this trivial `Color.clear` view — not `HomeView`, which renders the live Map.
/// That's what removes the detent-drag hitch.
///
/// `presentationBackgroundInteraction` is host-controller-wide, so the map (a
/// ZStack sibling of this view in `HomeView`) stays undimmed and interactive
/// behind the sheet even though it isn't this view's own content.
struct SheetHost: View {
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?
    @Binding var stop: StopWithDistance?
    /// Whether a detail is shown (computed on HomeView); drives the detent raise.
    let showingDetail: Bool
    /// Shared detent state (owned by HomeView). SheetHost binds the sheet to it.
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
