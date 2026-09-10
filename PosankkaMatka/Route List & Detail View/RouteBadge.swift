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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(route.color ?? .accentColor, in: .rect(cornerRadius: 6))
    }
}

#Preview {
    RouteBadge(route: Foli.Route(
        id: "1", shortName: "15", longName: "Kauppatori–Länsikeskus",
        type: 3, colorHex: "007AC9", textColorHex: "FFFFFF"
    ))
}
