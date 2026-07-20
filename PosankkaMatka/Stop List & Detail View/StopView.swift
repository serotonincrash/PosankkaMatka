//
//  TestStopView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import FoliBusUI
struct StopView: View {
    @Namespace var namespace
    var stopWithDistance: StopWithDistance
    @FoliService var foli
    @State var arrivalState: ResourceState<[Foli.Arrival]> = .loading
    
    var body: some View {
        Group {
            switch (arrivalState) {
            case .loading:
                ProgressView()
            case .success(let arrivals):
                VStack {
                    if arrivals.count == 0 {
                        ContentUnavailableView("No Arrivals", systemImage: "pc")
                    } else {
                        List {
                            Section("Arrivals") {
                                ForEach(arrivals) { arrival in
                                    HStack {
                                        Text(arrival.lineRef)
                                            .monospaced()
                                        Text(arrival.destinationDisplay)
                                        Spacer()
                                        Text(arrival.expectedDepartureDate.formattedInterval(to: .now))
                                            .font(.footnote)
                                    }
                                }
                                
                            }
                        }
                    }
                    
                }
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "pc", description: Text(error.localizedDescription))}
        }
        .refreshable {
            await refreshStop()
        }
        .task {
            await refreshStop()
        }
        .navigationTitle(Text(stopWithDistance.stop.name))
        
    }
    func refreshStop() async {
        do {
            let arrivalData = try await foli.fetchArrivals(for: stopWithDistance.stop.id)
            arrivalState = .success(arrivalData)
        } catch {
            arrivalState = .failure(error as? Foli.APIError ?? .networkError(error))
        }
    }
}
