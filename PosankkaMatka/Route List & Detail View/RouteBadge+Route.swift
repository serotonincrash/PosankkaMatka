//
//  RouteBadge+Route.swift
//  PosankkaMatka
//

import SwiftUI
import FoliBusUI

extension RouteBadge {
    init(route: Foli.Route) {
        self.init(name: route.shortName, color: route.color, textColor: route.textColor)
    }
}

#Preview {
    RouteBadge(route: Foli.Route(
        id: "1", shortName: "15", longName: "Kauppatori–Länsikeskus",
        type: 3, colorHex: "007AC9", textColorHex: "FFFFFF"
    ))
}
