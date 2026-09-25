//
//  SheetHost.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import Observation
import FoliBusUI

/// Shared sheet detents, owned by `HomeView` and bound only here, so per-drag
/// writes re-evaluate these trivial views — never `HomeView`/the Map.
@MainActor
@Observable
final class SheetModel {
    /// The peek detent. Inline titles leave the peek at the pre-summary
    /// height for now; it gets re-measured once a summary line exists.
    static let peek = PresentationDetent.height(110)
    /// Detent of the master lists sheet.
    var listDetent: PresentationDetent = .medium
    /// Detent of the detail card (stop or route content).
    var cardDetent: PresentationDetent = .medium
    /// Set while a programmatic cardDetent change should NOT trigger the
    /// detent reframe — the writer (stop selection) frames synchronously
    /// itself. Consumed by SheetHost's change handler.
    var suppressDetentReframe = false
}

/// Hosts the app's two sheets as siblings (never nested), isolated from the
/// map so detent drags invalidate only these views. Maps-style swap: the
/// master lists and ONE detail card exchange as whole sheets; within the card,
/// stop ⇄ route are content swaps — re-presenting mid-dismiss comes up with
/// default config, and a single morphing sheet flashed titles mid-swap.
/// Neither sheet is swipe-dismissable: a downward drag always collapses, and
/// the card's close button exits to the lists.
struct SheetHost: View {
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?
    @Binding var stop: StopWithDistance?
    /// Shared detents, bound to the sheets.
    @Bindable var sheetModel: SheetModel
    /// Detent-reframe callback, fired from here so per-drag detent reads stay
    /// out of `HomeView.body` (which would re-diff the Map on every write).
    let onCardDetentChange: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Master lists: up only when no card is; returns at its last detent.
            Color.clear
                .allowsHitTesting(false)   // never intercept taps meant for the map
                .sheet(isPresented: masterPresented) {
                    NavigationStack {
                        ListStopsView(selectedStopID: $selectedStopID, selectedRoute: $selectedRoute)
                    }
                    .presentationDetents([SheetModel.peek, .medium], selection: $sheetModel.listDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .interactiveDismissDisabled()
                }

            // The detail card: stop content wins over route; selections while
            // the card is up swap in place — no dismiss/present pair to race.
            Color.clear
                .allowsHitTesting(false)
                .sheet(isPresented: cardPresented) {
                    cardChrome {
                        if let stop {
                            StopView(stopWithDistance: stop)
                                // Fresh identity per stop → arrivals re-fetch.
                                .id(stop.id)
                                .transition(cardTransition)
                        } else if let selectedRoute {
                            RouteDetailList(route: selectedRoute, selectedStopID: $selectedStopID)
                                .transition(cardTransition)
                        }
                    }
                }
                .onChange(of: sheetModel.cardDetent) { _, _ in
                    // Programmatic resets (card swaps) frame synchronously at
                    // the selection site; only user drags reframe.
                    if sheetModel.suppressDetentReframe {
                        sheetModel.suppressDetentReframe = false
                    } else {
                        onCardDetentChange()
                    }
                }
        }
    }

    /// Card chrome: native titles, detents, close button. Swipe-down is
    /// disabled — a down-drag always collapses; the button exits to the lists.
    private func cardChrome(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack {
            ZStack {
                content()
            }
            .animation(.spring(duration: 0.3), value: stop)
            .animation(.spring(duration: 0.3), value: selectedRoute)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CardCloseButton {
                        // Exit to the lists from however deep the card is.
                        stop = nil
                        selectedRoute = nil
                    }
                }
            }
        }
        .presentationDetents([SheetModel.peek, .medium, .large], selection: $sheetModel.cardDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    /// The card content replacement: the new detail slides up over the old
    /// one — a plain fade under Reduce Motion.
    private var cardTransition: AnyTransition {
        .asymmetric(
            insertion: reduceMotion ? .opacity : .move(edge: .bottom),
            removal: .opacity
        )
    }

    /// Master shows exactly when no card is. No-op setter: the sheet can't be
    /// interactively dismissed; dismissal flows through the selection state.
    private var masterPresented: Binding<Bool> {
        Binding(
            get: { stop == nil && selectedRoute == nil },
            set: { _ in }
        )
    }

    /// Card shows while anything is selected; same no-op-setter reasoning.
    private var cardPresented: Binding<Bool> {
        Binding(
            get: { stop != nil || selectedRoute != nil },
            set: { _ in }
        )
    }
}

private struct CardCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Close")
        .accessibilityHint("Returns to the stop and route lists")
    }
}
