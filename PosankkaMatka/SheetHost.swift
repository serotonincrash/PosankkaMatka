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
    var selectedDetent: PresentationDetent = .medium
    /// Detent of the stop card.
    var stopDetent: PresentationDetent = .medium
    /// Detent of the route card.
    var routeDetent: PresentationDetent = .medium
}

/// Hosts the app's sheets in isolation from the map, so sheet-drag detent writes
/// invalidate only these trivial views — not `HomeView`, which renders the live
/// map. The map (a ZStack sibling) stays undimmed and tappable behind every sheet
/// via host-wide `presentationBackgroundInteraction`.
///
/// Maps-style presentation, without dismissal races: the master sheet stays
/// presented permanently, and the stop and route cards present OVER it (a stop
/// selection overlays the route card the same way). Swapping sheets by
/// dismiss-then-present — the literal Maps sequence — loses the incoming sheet's
/// presentation config (detents, grabber, background interaction) roughly half
/// the time when the presentation is queued behind a dismissal, so nothing here
/// ever dismisses and presents in the same transition. Dismissing a card simply
/// reveals the sheet beneath it, which also restores the master at its last
/// detent for free.
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
        Color.clear
            .allowsHitTesting(false)   // never intercept taps meant for the map
            .sheet(isPresented: .constant(true)) {
                NavigationStack {
                    ListStopsView(selectedStopID: $selectedStopID, selectedRoute: $selectedRoute)
                        // Card hosts live in the master's content: sheets
                        // present over the master from within, never beside it.
                        .background(
                            ZStack {
                                routeCard
                                stopCard(item: masterStopItem)
                                    .onChange(of: sheetModel.stopDetent) { _, _ in
                                        onCardDetentChange()
                                    }
                            }
                        )
                }
                .presentationDetents([.height(110), .medium], selection: $sheetModel.selectedDetent)
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .interactiveDismissDisabled()
            }
    }

    /// The route card over the lists. Its content hosts the stop card, so a stop
    /// selection (row tap or map marker behind the card) overlays the route card
    /// without dismissing it — dismissing the stop card reveals it again.
    private var routeCard: some View {
        Color.clear
            .allowsHitTesting(false)
            .sheet(item: $selectedRoute) { route in
                cardChrome($sheetModel.routeDetent) {
                    RouteDetailList(route: route, selectedStopID: $selectedStopID)
                        .background(
                            stopCard(item: $stop)
                                .onChange(of: sheetModel.stopDetent) { _, _ in
                                    onCardDetentChange()
                                }
                        )
                }
            }
            .onChange(of: sheetModel.routeDetent) { _, _ in
                onCardDetentChange()
            }
    }

    /// The stop card. Parameterized by item so the same host serves both nesting
    /// levels: the master hosts it only while no route card is up (otherwise its
    /// item is forced nil — the route card's content hosts the live one).
    private func stopCard(item: Binding<StopWithDistance?>) -> some View {
        Color.clear
            .allowsHitTesting(false)
            .sheet(item: item) { stop in
                cardChrome($sheetModel.stopDetent) {
                    StopView(stopWithDistance: stop)
                        // Fresh identity per stop → its store resets and
                        // re-fetches arrivals rather than reusing stale data.
                        .id(stop.id)
                }
            }
    }

    /// Shared detail-card chrome: a navigation context for titles, Maps-style
    /// detents with a drag indicator, a tappable map behind the card at
    /// `.medium`, and the Maps-style exit button (swipe-down also dismisses).
    private func cardChrome(_ detent: Binding<PresentationDetent>, @ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        CardCloseButton()
                    }
                }
        }
        .presentationDetents([.medium, .large], selection: detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
    }

    /// The master hosts the stop card only when it is the top sheet; while a
    /// route is selected the route card's content owns the presentation.
    private var masterStopItem: Binding<StopWithDistance?> {
        Binding(
            get: { selectedRoute == nil ? stop : nil },
            set: { stop = $0 }
        )
    }
}

/// Dismisses the card it sits in. Resolved inside the card's own presentation,
/// so it dismisses just that card (e.g. the stop card over the route card) and
/// writes `nil` back through the card's item binding, exactly like a swipe.
private struct CardCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
        }
        .accessibilityLabel("Close")
    }
}
