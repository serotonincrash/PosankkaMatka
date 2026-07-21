//
//  ContentView.swift
//  FoliAPITestApp
//
//  Created by sero on 25/2/26.
//

import SwiftUI
import FoliBusUI
import CoreLocation
import CoreLocationUI
import Forever

struct ListStopsView: View {
    @State var search = ""
    @Environment(ResourceStore<[Foli.Stop]>.self) private var stopsStore
    @Environment(LocationManager.self) var locationManager
    @Forever("nearbySearchFilter") var searchFilter: SearchList.SortState = .proximity(2000)
    @Environment(\.isSearching) var isSearching: Bool

    /// Selecting a stop from the list drives the same selection the map uses, so
    /// the map recenters/highlights and navigation happens on the shared stack.
    @Binding var selectedStopID: Foli.Stop.ID?

    var body: some View {
        // No NavigationStack here: this view lives inside HomeView's stack, which
        // owns the `navigationDestination`. A nested stack would trap pushes.
        Group {
            switch (stopsStore.state) {
            case .loading:
                ProgressView()
            case .success(let stops):
                SearchList(search: $search, stops: stops, searchFilter: $searchFilter, selectedStopID: $selectedStopID)
                    .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search by name or code"))
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "pc", description: Text(error.localizedDescription))
            }
        }
    }

}

#Preview {
    ListStopsView(selectedStopID: .constant(nil))
        .environment(ResourceStore<[Foli.Stop]>())
        .environment(LocationManager())
}
