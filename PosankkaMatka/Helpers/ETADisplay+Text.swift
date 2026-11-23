//
//  ETADisplay+Text.swift
//  PosankkaMatka
//

import SwiftUI
import PosankkaCore

/// One wording for arrival times, shared by the stop and vehicle cards.
extension ETADisplay {
    var text: Text {
        switch self {
        case .now: Text("Now")
        case .minutes(let minutes): Text("\(minutes) min")
        case .clock(let date): Text(date, format: .dateTime.hour().minute())
        }
    }

    /// VoiceOver form of `text`.
    var spoken: String {
        switch self {
        case .now: String(localized: "arriving now")
        case .minutes(let minutes): String(localized: "in \(minutes) minutes")
        case .clock(let date): String(localized: "at \(date.formatted(date: .omitted, time: .shortened))")
        }
    }
}
