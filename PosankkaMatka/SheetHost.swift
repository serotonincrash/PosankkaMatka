//
//  SheetHost.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import Observation
import FoliBusUI
import PosankkaCore

/// Sheet detents, bound only in `SheetHost` so drags don't re-render the map.
@MainActor
@Observable
final class SheetModel {
    static let peek = PresentationDetent.height(110)
    var listDetent: PresentationDetent = .medium
    var cardDetent: PresentationDetent = .medium
    /// Set before a programmatic `cardDetent` change whose writer frames the
    /// map itself, so the change handler skips its reframe.
    var suppressDetentReframe = false
}

/// The lists sheet and the detail card, as sibling sheets. Stop and route
/// swap as content inside one card: re-presenting mid-dismiss comes up with
/// default config. Neither sheet swipe-dismisses; the card has a close button.
struct SheetHost: View {
    let selection: Selection
    /// Setters run `HomeView`'s selection transitions.
    @Binding var selectedStopID: Foli.Stop.ID?
    @Binding var selectedRoute: Foli.Route?
    @Bindable var sheetModel: SheetModel
    let onClose: () -> Void
    let onCardDetentChange: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.clear
                .allowsHitTesting(false)
                .sheet(isPresented: masterPresented) {
                    NavigationStack {
                        ListStopsView(selectedStopID: $selectedStopID, selectedRoute: $selectedRoute)
                    }
                    .presentationDetents([SheetModel.peek, .medium], selection: $sheetModel.listDetent)
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .interactiveDismissDisabled()
                }

            Color.clear
                .allowsHitTesting(false)
                .sheet(isPresented: cardPresented) {
                    cardChrome {
                        if let stop = selection.stop {
                            StopView(stop: stop)
                                // New identity per stop, so arrivals re-fetch.
                                .id(stop.id)
                                .transition(cardTransition)
                        } else if let route = selection.route {
                            RouteDetailList(route: route, selectedStopID: $selectedStopID)
                                .transition(cardTransition)
                        }
                    }
                }
                .onChange(of: sheetModel.cardDetent) { _, _ in
                    if sheetModel.suppressDetentReframe {
                        sheetModel.suppressDetentReframe = false
                    } else {
                        onCardDetentChange()
                    }
                }
        }
    }

    private func cardChrome(@ViewBuilder _ content: () -> some View) -> some View {
        NavigationStack {
            ZStack {
                content()
            }
            .animation(.spring(duration: 0.3), value: selection)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CardCloseButton(action: onClose)
                }
            }
        }
        .presentationDetents([SheetModel.peek, .medium, .large], selection: $sheetModel.cardDetent)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()
    }

    private var cardTransition: AnyTransition {
        .asymmetric(
            insertion: reduceMotion ? .opacity : .move(edge: .bottom),
            removal: .opacity
        )
    }

    /// No-op setters: the sheets can't be dismissed interactively.
    private var masterPresented: Binding<Bool> {
        Binding(
            get: { selection.isEmpty },
            set: { _ in }
        )
    }

    private var cardPresented: Binding<Bool> {
        Binding(
            get: { !selection.isEmpty },
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
