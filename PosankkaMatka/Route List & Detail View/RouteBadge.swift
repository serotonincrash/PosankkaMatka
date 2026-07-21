//
//  RouteBadge.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import SwiftUI
import FoliBusUI

/// A compact colored badge showing a route's line number, using the route's own
/// GTFS colors. Reusable in the route list and (eventually) stop cells.
struct RouteBadge: View {
    let route: Foli.Route

    var body: some View {
        Text(route.shortName)
            .font(.subheadline.weight(.bold))
            .monospaced()
            .foregroundStyle(route.textColor ?? .white)
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
