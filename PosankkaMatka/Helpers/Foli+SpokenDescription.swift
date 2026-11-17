//
//  Foli+SpokenDescription.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//

import Foundation
import FoliBusUI

extension Foli.Route {
    /// VoiceOver row label.
    var spokenDescription: String {
        String(localized: "Route \(shortName), \(longName)")
    }
}
