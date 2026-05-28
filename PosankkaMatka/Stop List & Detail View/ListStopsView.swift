//
//  ContentView.swift
//  FoliAPITestApp
//
//  Created by sero on 25/2/26.
//

import SwiftUI
import FoliBusAPI
import CoreLocation
import CoreLocationUI
struct ListStopsView: View {
    @FoliService var foli
    @State var search = ""
    @State var stopState: ResourceState<[Foli.Stop]> = .loading
    
    @Environment(\.isSearching) var isSearching: Bool
    var body: some View {
        NavigationStack {
                switch (stopState) {
                case .loading:
                    ProgressView()
                case .success(let stops):
                    SearchList(search: $search, stops: stops)
                        .searchable(text: $search, prompt: Text("Search by name or code"))
                case .failure(let error):
                    ContentUnavailableView("Error", systemImage: "pc", description: Text(error.localizedDescription))
                }
        }

        .task {
            do {
                let stopData = try await foli.fetchStops()
                stopState = .success(stopData)
            } catch {
                stopState = .failure(error as? Foli.APIError ?? .networkError(error))
            }
        }
        
    }
    
    enum SortState: Hashable {
        /// Filter stops out based on proximity in meters
        case proximity(Double)
        
        /// Show all stops
        case none
    }
    
}

#Preview {
    ListStopsView()
}
