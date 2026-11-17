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
                code
                Text(name)
            }
        } else {
            HStack {
                code
                Text(name)
            }
        }
    }

    private var code: some View {
        Text(stopID)
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
