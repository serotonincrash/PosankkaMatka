//
//  VehicleCardView.swift
//  PosankkaMatka
//

import SwiftUI
import CoreLocation
import FoliBusUI
import PosankkaCore

/// One bus's trip as a live stop rail. Pops itself a few seconds after the
/// trip ends or the bus is lost.
struct VehicleCardView: View {
    let key: TripKey

    var body: some View {
        // The rail's ETAs and the stale note tick; positions change per poll.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VehicleCardContent(key: key, now: context.date)
        }
        .navigationTitle("Bus \(key.lineRef)")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private enum Ending: Equatable {
    case ended(terminus: String?)
    case lost
}

private enum Phase: Equatable {
    case pending, live, stale, ended, lost
}

private struct VehicleCardContent: View {
    let key: TripKey
    let now: Date
    @Environment(AppModel.self) private var model

    @State private var ending: Ending?
    /// Shown after the trip ends or is lost, when the tracker no longer has the bus.
    @State private var lastJourney: VehicleJourney?
    @State private var userScrolled = false

    private var tracked: (journey: VehicleJourney, position: VehicleTracker.Position, lastSeen: Date?)? {
        guard let tracked = model.journey(at: now), tracked.journey.trip.vehicleRef == key.vehicleRef else { return nil }
        return tracked
    }

    private var phase: Phase {
        switch model.tripStatus(at: now) {
        case .live: .live
        case .stale: .stale
        case .ended: .ended
        case .lost: .lost
        case .pending, nil: .pending
        }
    }

    private var route: Foli.Route? { model.route(forLine: key.lineRef) }
    private var routeColor: Color { route?.color ?? .accentColor }

    var body: some View {
        let tracked = tracked
        let journey = tracked?.journey ?? lastJourney
        Group {
            if let journey {
                rail(journey, lastSeen: tracked?.lastSeen)
            } else if ending == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List { Section { header(nil) } }
                    .safeAreaInset(edge: .top, spacing: 0) { statusLine(nil, lastSeen: nil) }
            }
        }
        .onChange(of: tracked?.position.vehicle, initial: true) { _, _ in
            if let journey = tracked?.journey { lastJourney = journey }
        }
        .onChange(of: phase, initial: true) { _, phase in
            handle(phase)
        }
        .onChange(of: alertEstimate(in: tracked?.journey)) { _, estimate in
            guard let estimate, let journey = tracked?.journey else { return }
            Task {
                await model.stopAlert.update(
                    eta: estimate.eta,
                    nextStopName: estimate.nextStopName,
                    delaySeconds: journey.delay.map { Int($0) }
                )
            }
        }
        .sensoryFeedback(trigger: ending) { _, new in
            if case .ended = new { .success } else { nil }
        }
        .task(id: ending) {
            guard ending != nil else { return }
            try? await Task.sleep(for: .seconds(3))
            // Cancelled when the card leaves; skip if something was pushed over it.
            guard !Task.isCancelled, model.selection.vehicle == key else { return }
            model.closeTop()
        }
    }

    // MARK: - Ending

    private func handle(_ phase: Phase) {
        guard ending == nil else { return }
        switch phase {
        case .ended:
            ending = .ended(terminus: lastJourney?.terminus?.name ?? lastJourney?.destinationName)
        case .lost:
            ending = .lost
        default:
            return
        }
        AccessibilityNotification.Announcement(endingText).post()
        if let attributes = model.stopAlert.active?.attributes,
           attributes.vehicleRef == key.vehicleRef,
           attributes.originAimedDepartureTime == key.originAimedDepartureTime {
            Task { await model.stopAlert.cancel() }
        }
    }

    private var endingText: String {
        switch ending {
        case .ended(let terminus?): String(localized: "Trip ended at \(terminus)")
        case .ended(nil): String(localized: "Trip ended")
        case .lost: String(localized: "Lost contact with bus \(key.lineRef)")
        case nil: ""
        }
    }

    // MARK: - Rail

    private func rail(_ journey: VehicleJourney, lastSeen: Date?) -> some View {
        let slices = RailSlice.slices(for: journey, allPassed: isEnded)
        return ScrollViewReader { proxy in
            List {
                Section {
                    header(journey)
                }
                Section {
                    ForEach(journey.calls) { call in
                        row(call, slice: slices[call.id], journey: journey)
                            .id(call.id)
                    }
                } footer: {
                    alertFooter
                }
            }
            .listStyle(.plain)
            // Pinned: auto-scroll to the current stop would push freshness and
            // the ending banner off-screen.
            .safeAreaInset(edge: .top, spacing: 0) { statusLine(journey, lastSeen: lastSeen) }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { userScrolled = true }
            }
            .onChange(of: journey.nextStopIndex, initial: true) { _, index in
                guard !userScrolled, ending == nil, let index else { return }
                withAnimation { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private var isEnded: Bool {
        if case .ended = ending { true } else { false }
    }

    private func row(_ call: VehicleJourney.Call, slice: RailSlice, journey: VehicleJourney) -> some View {
        let isAlerting = model.stopAlert.isAlerting(stopID: call.stopID, trip: journey.trip)
        let isAhead = call.state != .passed && ending == nil
        return Button {
            if let stop = model.stop(withID: call.stopID) { model.selectStop(stop) }
        } label: {
            HStack(spacing: 12) {
                RailGutter(slice: slice, color: routeColor)
                StopRowLabel(stopID: call.stopID, name: call.name)
                    .foregroundStyle(call.state == .passed ? .secondary : .primary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isAlerting {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(routeColor)
                        .accessibilityHidden(true)
                }
                if isAhead, let eta = call.estimatedArrival(delay: journey.delay) {
                    etaText(ETADisplay(arrival: eta, now: now))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(call.state == .upcoming ? .secondary : .primary)
                }
            }
        }
        .tint(.primary)
        .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenRow(call, journey: journey, isAlerting: isAlerting))
        .accessibilityHint("Opens live arrivals for this stop")
        .accessibilityAddTraits(.isButton)
        .stopInputLabels(stopID: call.stopID, name: call.name)
        .contextMenu {
            if isAhead, call.coordinate != nil, call.estimatedArrival(delay: journey.delay) != nil {
                if isAlerting {
                    Button("Cancel Alert", systemImage: "bell.slash") {
                        Task { await model.stopAlert.cancel() }
                    }
                } else {
                    Button("Alert Me Here", systemImage: "bell") {
                        Task { await setAlert(at: call, journey: journey) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func etaText(_ display: ETADisplay) -> some View {
        switch display {
        case .now: Text("Now")
        case .minutes(let minutes): Text("\(minutes) min")
        case .clock(let date): Text(date, format: .dateTime.hour().minute())
        }
    }

    private func spokenRow(_ call: VehicleJourney.Call, journey: VehicleJourney, isAlerting: Bool) -> String {
        var parts = [String(localized: "Stop ID \(call.stopID), \(call.name)")]
        if call.state == .passed || ending != nil {
            parts.append(String(localized: "Passed"))
        } else if let eta = call.estimatedArrival(delay: journey.delay) {
            let time = spokenETA(ETADisplay(arrival: eta, now: now))
            if case .current = call.state {
                parts.append(String(localized: "Next stop, \(time)"))
            } else {
                parts.append(time)
            }
        }
        if isAlerting { parts.append(String(localized: "Alert set")) }
        return parts.joined(separator: ", ")
    }

    private func spokenETA(_ display: ETADisplay) -> String {
        switch display {
        case .now: String(localized: "arriving now")
        case .minutes(let minutes): String(localized: "in \(minutes) minutes")
        case .clock(let date): String(localized: "at \(date.formatted(date: .omitted, time: .shortened))")
        }
    }

    // MARK: - Header

    private func header(_ journey: VehicleJourney?) -> some View {
        HStack(spacing: 12) {
            if let route { RouteBadge(route: route) }
            if let destination = journey?.destinationName {
                Text(destination).font(.headline)
            }
        }
        .accessibilityElement(children: .combine)
        .listRowSeparator(.hidden)
    }

    /// Delay and freshness, or the ending banner, above the scrolling rail.
    @ViewBuilder
    private func statusLine(_ journey: VehicleJourney?, lastSeen: Date?) -> some View {
        if ending != nil {
            Label(endingText, systemImage: isEnded ? "flag.checkered" : "antenna.radiowaves.left.and.right.slash")
                .font(.subheadline.weight(.semibold))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.thinMaterial, in: .rect(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.bottom, 8)
        } else if journey?.delay != nil || lastSeen != nil {
            HStack(spacing: 6) {
                if let delay = journey?.delay {
                    delayText(delay)
                        .foregroundStyle(delay >= 60 ? .orange : .secondary)
                }
                if journey?.delay != nil, lastSeen != nil {
                    Text(verbatim: "·").foregroundStyle(.secondary).accessibilityHidden(true)
                }
                if let lastSeen {
                    Text("Updated \(Text(lastSeen, format: .relative(presentation: .named)))")
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.horizontal)
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private func delayText(_ delay: TimeInterval) -> Text {
        let minutes = Int((abs(delay) / 60).rounded())
        if minutes == 0 { return Text("On time") }
        return delay > 0 ? Text("\(minutes) min late") : Text("\(minutes) min early")
    }

    // MARK: - Stop alert

    @ViewBuilder
    private var alertFooter: some View {
        let alert = model.stopAlert
        if let active = alert.active, active.attributes.vehicleRef == key.vehicleRef {
            if alert.isLocationDenied {
                Text("Location access is off, so this alert can't fire. Turn it on in Settings.")
            } else if !alert.canAlertInBackground {
                Text("This alert works only while the app is open. Allow location access Always in Settings to be alerted in the background.")
            }
        }
    }

    private struct AlertEstimate: Equatable {
        var eta: Date
        var nextStopName: String?
    }

    /// The alerting stop's estimate; changes per poll, not per frame.
    private func alertEstimate(in journey: VehicleJourney?) -> AlertEstimate? {
        guard let journey, let stopID = model.stopAlert.active?.attributes.stopID,
              model.stopAlert.isAlerting(stopID: stopID, trip: journey.trip),
              let call = journey.calls.first(where: { $0.stopID == stopID && $0.state != .passed }),
              let eta = call.estimatedArrival(delay: journey.delay) else { return nil }
        let next = journey.nextStopIndex.map { journey.calls[$0].name }
        return AlertEstimate(eta: eta, nextStopName: next)
    }

    private func setAlert(at call: VehicleJourney.Call, journey: VehicleJourney) async {
        guard let coordinate = call.coordinate,
              let eta = call.estimatedArrival(delay: journey.delay) else { return }
        let attributes = StopAlertAttributes(
            trip: journey.trip,
            lineName: journey.trip.lineRef,
            route: route,
            destinationName: journey.destinationName,
            stopID: call.stopID,
            stopName: call.name
        )
        let next = journey.nextStopIndex.map { journey.calls[$0].name }
        await model.stopAlert.setAlert(
            attributes,
            at: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
            state: .init(eta: eta, updatedAt: .now, nextStopName: next, delaySeconds: journey.delay.map { Int($0) })
        )
    }
}
