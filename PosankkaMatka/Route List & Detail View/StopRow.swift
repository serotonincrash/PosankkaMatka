//
//  StopRow.swift
//  PosankkaMatka
//

import SwiftUI

/// A stop's code and name, shared by the route and vehicle rails. Stacked at
/// accessibility sizes.
struct StopRowLabel: View {
    let stopID: String
    let name: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                StopCode(id: stopID)
                Text(name)
            }
        } else {
            HStack {
                StopCode(id: stopID)
                Text(name)
            }
        }
    }
}

/// A stop's code, secondary and monospaced.
struct StopCode: View {
    let id: String

    var body: some View {
        Text(id)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospaced()
    }
}

extension View {
    /// Voice Control gets the short forms.
    func stopInputLabels(stopID: String, name: String) -> some View {
        accessibilityInputLabels(["\(stopID) \(name)", name])
    }
}
