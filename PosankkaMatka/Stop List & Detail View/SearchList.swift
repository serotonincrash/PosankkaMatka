//
//  SearchList.swift
//  PosankkaMatka
//
//  Created by sero on 8/4/26.
//

import SwiftUI
import CoreLocation
import FoliBusUI
import Forever

struct SearchList: View {
    @Namespace var namespace
    
    @Environment(\.isSearching) var isSearching
    @Environment(LocationManager.self) var locationManager
    
    @Binding var search: String
    @State var stops: [Foli.Stop]
    @Binding var searchFilter: SortState
    var body: some View {
        if !isSearching {
            let filteredStops = filter(stops)
            
            VStack {
                if filteredStops.isEmpty {
                    ContentUnavailableView("No Stops", systemImage: "questionmark", description: Text(searchFilter == .none ? "There are no stops available." : "There are no stops matching the given criteria."))
                } else {
                    List(filteredStops) { stopWithDistance in
                        NavigationLink {
                            StopView(stopWithDistance: stopWithDistance)
                        } label: {
                            HStack {
                                Text(stopWithDistance.stop.id)
                                    .monospaced()
                                Text(stopWithDistance.stop.name)
                                Spacer()
                                Group {
                                    if let distance = stopWithDistance.distance {
                                        Text(distance < 1000 ? "\(Int(distance)) m" : "\((distance / 1000).formatted(toDecimalPlaces: 2)) km")
                                            .font(.subheadline)
                                    }
                                }
                                
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("Nearby"))
            .toolbar {
                Menu {
                    Button {
                        searchFilter = .none
                    } label: {
                        if searchFilter == .none {
                            Image(systemName: "checkmark")
                                .imageScale(.small)
                        }
                        Label("None", systemImage: "location.slash")
                    }
                    
                    Section("Distance") {
                        Picker(selection: $searchFilter) {
                            
                            Text("500 m")
                                .tag(SortState.proximity(500))
                            Text("1 km")
                                .tag(SortState.proximity(1000))
                            Text("2 km")
                                .tag(SortState.proximity(2000))
                            
                        } label: {
                            Label("Filter by Proximity", systemImage: "location")
                        }
                    }
                } label: {
                    Image(systemName: "location")
                }
                
            }
        } else {
            Group {
                if !search.isEmpty {
                    let filteredStops = stops.filter({ stop in
                        stop.name.lowercased().contains(search.lowercased()) || (stop.code ?? "").lowercased().contains(search.lowercased())
                    })
                    if filteredStops.isEmpty {
                        ContentUnavailableView {
                            Label("No Stops", systemImage: "questionmark")
                        } description: {
                            Text("No stops matching the given criteria were found.")
                        } actions: {
                            Button("All Stops") {
                                self.searchFilter = .none
                            }
                        }
                    } else {
                        VStack {
                            List(filteredStops) { stop in
                                NavigationLink {
                                    StopView(stopWithDistance: .init(stop))
//                                        .navigationTransition(.zoom(sourceID: stop.id + stop.name, in: namespace))
                                } label: {
                                    #warning("TODO turn this into a cell showing the routes too?")
                                    HStack {
                                        Text(stop.id)
                                            .monospaced()
                                        Text(stop.name)
//                                            .matchedTransitionSource(id: stop.id + stop.name, in: namespace)
                                        
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Start typing!", systemImage: "magnifyingglass", description: Text("Type a stop name or code to start searching."))
                }
            }
        }
    }
    
    func filter(_ stops: [Foli.Stop]) -> [StopWithDistance] {
        var sortedStops = stops.sorted(by: { s1, s2 in
            Int(s1.id)! < Int(s2.id)!
        })
        
        if locationManager.checkLocationAuthorization() {
            guard let location = locationManager.currentLocation, let currCLLocation = CLLocation(location) else { return sortedStops.map { .init($0) } }
            
            if case .proximity(let distance) = searchFilter, distance > 0 {
                sortedStops = sortedStops.filter(byDistance: distance, from: currCLLocation)
            }
            
            sortedStops = sortedStops.sortedByDistance(to: currCLLocation)
            return sortedStops.map {
                if let stopLocation = $0.location, let stopCoord = CLLocation(stopLocation.toCLCoordinate()) {
                    StopWithDistance($0, distance: currCLLocation.distance(from: stopCoord))
                } else {
                    // invalid stop location?
                    StopWithDistance($0)
                }
            }
        } else {
            
            return sortedStops.map { StopWithDistance($0) }
        }
    }
    
    enum SortState: Hashable, Codable {
        /// Filter stops out based on proximity in meters
        case proximity(Double)
        
        /// Show all stops
        case none
    }
}
