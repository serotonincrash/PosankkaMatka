//
//  Foli+SpokenDescription.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import FoliBusUI

extension Foli.Route {
    /// Row label for screen readers ("Route 15, Kauppatori–Länsikeskus").
    var spokenDescription: String {
        "Route \(shortName), \(longName)"
    }
}
