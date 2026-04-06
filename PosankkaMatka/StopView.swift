//
//  TestStopView.swift
//  PosankkaMatka
//
//  Created by sero on 6/4/26.
//

import SwiftUI
import FoliBusAPI
struct StopView: View {
    var stopId: String
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
                        List(arrivals) { arrival in
                            HStack {
                                Text(arrival.lineRef)
                                    .monospaced()
                                Text(arrival.destinationDisplay)
                                Spacer()
                                Text(arrival.expectedDepartureDate.formatted(.iso8601))
                            }
                            .refreshable {
                                await refreshStop()
                            }
                        }
                    }
                    
                }
            case .failure(let error):
                ContentUnavailableView("Error", systemImage: "pc", description: Text(error.localizedDescription))}
        }
        .task {
            await refreshStop()
        }
        
    }
    func refreshStop() async {
        do {
            let arrivalData = try await foli.fetchArrivals(for: stopId)
            arrivalState = .success(arrivalData)
        } catch {
            arrivalState = .failure(error as? Foli.APIError ?? .networkError(error))
        }
    }
}

#Preview {
    StopView(stopId: "4")
}
