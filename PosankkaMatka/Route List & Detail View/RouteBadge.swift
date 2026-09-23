//
//  RouteBadge.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import FoliBusUI

/// A route's colored line-number badge (route's GTFS colors), fixed to a
/// three-character width.
struct RouteBadge: View {
    let route: Foli.Route

    /// Shared monospaced font, so the hidden reference and visible text measure identically.
    private var badgeFont: Font { .subheadline.weight(.bold).monospaced() }
    /// Chrome tracks the badge text under Dynamic Type instead of pinning.
    @ScaledMetric(relativeTo: .subheadline) private var hPadding: CGFloat = 8
    @ScaledMetric(relativeTo: .subheadline) private var vPadding: CGFloat = 4
    @ScaledMetric(relativeTo: .subheadline) private var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            // Invisible reference reserving a three-digit width. Longer codes
            // (e.g. the "Lautta" ferry) still expand beyond it naturally.
            Text("000")
                .font(badgeFont)
                .hidden()
            Text(route.shortName)
                .font(badgeFont)
                .foregroundStyle(route.textColor ?? .white)
        }
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .background(route.color ?? .accentColor, in: .rect(cornerRadius: cornerRadius))
    }
}

#Preview {
    RouteBadge(route: Foli.Route(
        id: "1", shortName: "15", longName: "Kauppatori–Länsikeskus",
        type: 3, colorHex: "007AC9", textColorHex: "FFFFFF"
    ))
}
