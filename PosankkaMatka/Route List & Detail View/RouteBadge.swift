//
//  RouteBadge.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import FoliBusUI

/// A compact colored badge showing a route's line number, using the route's own
/// GTFS colors. Fixed to a three-character width so badges align across rows
/// whether the line is "1", "15", or "180".
struct RouteBadge: View {
    let route: Foli.Route

    /// Monospaced, so a fixed three-glyph width is meaningful; shared by the
    /// hidden reference and the visible text so both measure identically (and
    /// scale together with Dynamic Type).
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
