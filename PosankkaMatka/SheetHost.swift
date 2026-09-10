//
//  SheetHost.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import Observation
import FoliBusUI

/// Shared sheet detents, owned by `HomeView`. Only `SheetHost` binds them and only
/// framing methods read them — `body` must not, or it re-subscribes to per-drag-frame
/// writes.
@MainActor
@Observable
final class SheetModel {
    /// Detent of the master lists sheet.
    var listDetent: PresentationDetent = .medium
    /// Detent of the detail card (stop or route content).
    var cardDetent: PresentationDetent = .medium
}

/// Hosts the app's two sheets in isolation from the map, so sheet-drag detent
/// writes invalidate only these trivial views — not `HomeView`, which renders
/// the live map. The sheets are siblings — never nested — so every detent drag
/// acts on the one visible sheet. The map (a ZStack sibling) stays undimmed and
/// tappable behind every sheet via host-wide `presentationBackgroundInteraction`.
///
/// Maps-style swap: the master lists and ONE detail card swap as whole sheets
/// (dismiss + present, sequenced by UIKit). Within the card, stop and route
/// details are content swaps — never re-presentations — because presenting a
/// new sheet while the old one dismisses (e.g. stop over route) reliably came
/// up with default config (full height, no detents or grabber). (A single
/// never-dismissed morphing sheet was tried instead: the shared navigation bar
/// flashes between the lists' and the card's titles mid-swap, and in-content
/// headers are a UI regression — cards keep native titles in their own stack.)
///
/// Neither sheet is swipe-dismissable: the master leaves only when a card
/// presents, the card only via its close button, which always exits to the
/// lists (from however deep the card is) — so a downward detent drag always
/// means "collapse", down to the shared peek. The master returns at its last
/// detent; a fresh card opens at `.medium` (set in `HomeView`'s selection
/// handlers), while swaps within an open card keep the user's detent.
struct SheetHost: View {
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?
    @Binding var stop: StopWithDistance?
    /// Shared detents, bound to the sheets.
    @Bindable var sheetModel: SheetModel
    /// Reframes the map selection on card detent changes. Fired from HERE so
    /// per-drag detent writes invalidate only this view — reading them from
    /// `HomeView.body` (e.g. `onChange(of:)`) would re-subscribe `HomeView` and
    /// re-diff the Map on every write.
    let onCardDetentChange: () -> Void

    var body: some View {
        ZStack {
            // Master lists: up only when no card is. Never dismissable — it
            // leaves only when a card presents, and returns (at its last
            // detent) when that card goes away.
            Color.clear
                .allowsHitTesting(false)   // never intercept taps meant for the map
                .sheet(isPresented: masterPresented) {
                    NavigationStack {
                        ListStopsView(selectedStopID: $selectedStopID, selectedRoute: $selectedRoute)
                    }
                    .presentationDetents([.height(110), .medium], selection: $sheetModel.listDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .interactiveDismissDisabled()
                }

            // The detail card: stop content when a stop is selected (winning
            // over route content), else route content. Selecting a stop while
            // the card is already up just swaps the content — no
            // dismissal/presentation pair to race.
            Color.clear
                .allowsHitTesting(false)
                .sheet(isPresented: cardPresented) {
                    cardChrome {
                        if let stop {
                            StopView(stopWithDistance: stop)
                                // Fresh identity per stop → its store resets and
                                // re-fetches arrivals rather than reusing stale data.
                                .id(stop.id)
                                .transition(cardTransition)
                        } else if let selectedRoute {
                            RouteDetailList(route: selectedRoute, selectedStopID: $selectedStopID)
                                .transition(cardTransition)
                        }
                    }
                }
                .onChange(of: sheetModel.cardDetent) { _, _ in
                    onCardDetentChange()
                }
        }
    }

    /// The detail-card chrome: a navigation context for native titles, Maps-
    /// style detents (peek to large) with a drag indicator, a tappable map
    /// behind the card up to `.medium`, and the close button. Content swaps
    /// (stop ⇄ route) slide the new content up over the old. Swipe-down is
    /// disabled so a downward drag always collapses the card, never dismisses
    /// it — the button always exits to the lists.
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
                        // Always exit to the lists, from however deep the card
                        // is (stop-over-route included).
                        stop = nil
                        selectedRoute = nil
                    }
                }
            }
        }
        .presentationDetents([.height(110), .medium, .large], selection: $sheetModel.cardDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    /// The card content replacement: the new detail slides up over the old one.
    private var cardTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .bottom), removal: .opacity)
    }

    /// The master shows exactly when no card is up. The no-op setter is safe:
    /// the master can't be interactively dismissed, and programmatic dismissal
    /// flows through the selection state that feeds `get`.
    private var masterPresented: Binding<Bool> {
        Binding(
            get: { stop == nil && selectedRoute == nil },
            set: { _ in }
        )
    }

    /// The card shows while anything is selected. Same no-op-setter reasoning:
    /// the card can't be interactively dismissed, and the close button pops by
    /// mutating the selection state.
    private var cardPresented: Binding<Bool> {
        Binding(
            get: { stop != nil || selectedRoute != nil },
            set: { _ in }
        )
    }
}

/// Closes the card via the given action — exits to the lists from however deep
/// the card is, unlike `\.dismiss`, which would tear down the whole card the
/// same way but reads less intentionally here.
private struct CardCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Close")
    }
}
