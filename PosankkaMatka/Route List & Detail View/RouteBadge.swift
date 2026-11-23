//
//  RouteBadge.swift
//  PosankkaMatka
//
//  Created by sero on 7/22/26.
//
//  Shared with the widget extension: SwiftUI only. `init(route:)` lives in
//  RouteBadge+Route.swift, since the widget doesn't link FoliBusUI.
//

import SwiftUI

/// A route's colored line-number badge, at least three characters wide.
struct RouteBadge: View {
    let name: String
    var color: Color?
    var textColor: Color?

    /// Shared so the hidden reference and visible text measure the same.
    private var badgeFont: Font { .subheadline.weight(.bold).monospaced() }
    @ScaledMetric(relativeTo: .subheadline) private var hPadding: CGFloat = 8
    @ScaledMetric(relativeTo: .subheadline) private var vPadding: CGFloat = 4
    @ScaledMetric(relativeTo: .subheadline) private var cornerRadius: CGFloat = 6

    var body: some View {
        ZStack {
            // Hidden reference reserves three-digit width; longer codes ("Lautta") still grow.
            Text("000")
                .font(badgeFont)
                .hidden()
            Text(name)
                .font(badgeFont)
                .foregroundStyle(textColor ?? .white)
        }
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .background(color ?? .accentColor, in: .rect(cornerRadius: cornerRadius))
    }
}
