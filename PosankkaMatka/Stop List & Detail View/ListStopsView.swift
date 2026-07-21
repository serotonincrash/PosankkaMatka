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
    var body: some View {
        NavigationStack {
            switch (stopsStore.state) {
            case .loading:
                ProgressView()
            case .success(let stops):
                SearchList(search: $search, stops: stops, searchFilter: $searchFilter)
                    .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search by name or code"))
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "pc", description: Text(error.localizedDescription))
            }
        }
    }

}

#Preview {
    ListStopsView()
        .environment(ResourceStore<[Foli.Stop]>())
        .environment(LocationManager())
}
