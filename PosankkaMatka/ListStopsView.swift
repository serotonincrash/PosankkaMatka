//
//  ContentView.swift
//  FoliAPITestApp
//
//  Created by sero on 25/2/26.
//

import SwiftUI
import FoliBusAPI

struct ListStopsView: View {
    @FoliService var foli
    @State var search = ""
    @State var stopState: ResourceState<[Foli.Stop]> = .loading
    var body: some View {
        NavigationStack {
            switch (stopState) {
            case .loading:
                ProgressView()
            case .success(let stops):
                VStack {
                    List(stops.sorted(by: { s1, s2 in
                        Int(s1.id)! < Int(s2.id)!
                    }).filter({ search == "" ? true : $0.displayName.lowercased().contains(search)})) { stop in
                        NavigationLink {
                            StopView(stopId: stop.id)
                        } label: {
                            HStack {
                                Text(stop.id)
                                    .monospaced()
                                Text(stop.displayName)
                                
                            }
                        }
                        
                    }
                    
                    .searchable(text: $search, prompt: Text("Stop Name"))
                }
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
}

#Preview {
    ListStopsView()
}
