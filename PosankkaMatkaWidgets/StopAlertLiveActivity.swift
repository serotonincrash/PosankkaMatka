//
//  StopAlertLiveActivity.swift
//  PosankkaMatkaWidgets
//

import ActivityKit
import SwiftUI
import WidgetKit

/// Countdown to the bus reaching the rider's alert stop.
struct StopAlertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StopAlertAttributes.self) { context in
            LockScreenView(context: context)
                .padding()
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LineBadge(attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(context: context)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.stopName)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    StatusLine(context: context)
                }
            } compactLeading: {
                LineBadge(attributes: context.attributes)
            } compactTrailing: {
                Countdown(context: context)
                    .frame(maxWidth: 52)
            } minimal: {
                // A full badge doesn't fit; the line number in its colour does.
                Text(context.attributes.lineName)
                    .font(.caption2.weight(.bold).monospaced())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(Color(hex: context.attributes.lineColorHex) ?? .accentColor)
                    .accessibilityLabel("Line \(context.attributes.lineName)")
            }
            .keylineTint(Color(hex: context.attributes.lineColorHex) ?? .accentColor)
        }
    }
}

private struct LockScreenView: View {
    let context: ActivityViewContext<StopAlertAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            LineBadge(attributes: context.attributes)
            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.stopName)
                    .font(.headline)
                    .lineLimit(1)
                StatusLine(context: context)
            }
            Spacer(minLength: 8)
            Countdown(context: context)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}

/// The rider's distance to the stop, or why the countdown can't be trusted.
private struct StatusLine: View {
    let context: ActivityViewContext<StopAlertAttributes>

    var body: some View {
        Group {
            if context.state.hasArrived {
                Text("Your stop is coming up")
            } else if context.state.busPassed {
                Text("The bus has passed the stop")
            } else if context.isStale, Date.now >= context.state.estimateExpiry {
                Text("Last updated \(context.state.updatedAt, style: .time)")
            } else if let distance = distanceText {
                distance
            } else if let next = context.state.nextStopName {
                Text("Next: \(next)")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// "You're 600 m away (8 min walk)".
    private var distanceText: Text? {
        guard let meters = context.state.distanceMeters else { return nil }
        let distance = Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
        if let walk = context.state.walkingMinutes {
            return Text("You're \(distance) away (\(walk) min walk)")
        }
        return Text("You're \(distance) away")
    }
}

private struct Countdown: View {
    let context: ActivityViewContext<StopAlertAttributes>

    private var state: StopAlertAttributes.ContentState { context.state }

    var body: some View {
        if state.hasArrived {
            Image(systemName: "bell.fill")
                .accessibilityLabel("Arriving")
        } else if state.busPassed {
            Image(systemName: "checkmark")
                .accessibilityLabel("Passed")
        } else if context.isStale, Date.now >= state.eta {
            // The staleDate includes the ETA, so this re-renders when the timer runs out.
            Text("Now")
        } else {
            // A range can't run backwards.
            Text(timerInterval: min(state.updatedAt, state.eta)...state.eta, countsDown: true)
                .monospacedDigit()
        }
    }
}

/// The app's `RouteBadge`, fed from the attributes.
private struct LineBadge: View {
    let attributes: StopAlertAttributes

    var body: some View {
        RouteBadge(
            name: attributes.lineName,
            color: Color(hex: attributes.lineColorHex),
            textColor: Color(hex: attributes.lineTextColorHex)
        )
        .accessibilityLabel("Line \(attributes.lineName)")
    }
}

private extension Color {
    /// GTFS colours are six hex digits without a leading #.
    init?(hex: String?) {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

#Preview("Lock Screen", as: .content, using: StopAlertAttributes(
    lineName: "15", lineColorHex: "007AC9", lineTextColorHex: "FFFFFF",
    destinationName: "Satama", stopID: "1", stopName: "Kauppatori",
    vehicleRef: "v1", lineRef: "15", originAimedDepartureTime: nil
)) {
    StopAlertLiveActivity()
} contentStates: {
    StopAlertAttributes.ContentState(eta: .now.addingTimeInterval(420), updatedAt: .now,
                                     nextStopName: "Puolalanmäki",
                                     distanceMeters: 600, walkingMinutes: 10)
    StopAlertAttributes.ContentState(eta: .now, updatedAt: .now, hasArrived: true)
    StopAlertAttributes.ContentState(eta: .now, updatedAt: .now, busPassed: true)
}
