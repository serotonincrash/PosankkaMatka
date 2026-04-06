//
//  HomeView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI

struct HomeView: View {
    var body: some View {
        TabView {
            Tab("Stops", systemImage: "house.and.flag") {
                ListStopsView()
            }
        }
    }
}

#Preview {
    HomeView()
}
