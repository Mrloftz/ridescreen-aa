// SPDX-License-Identifier: AGPL-3.0-or-later
import SwiftUI

@MainActor
@main
struct RideScreenApp: App {
    @StateObject private var recorder = TripRecorder()
    @StateObject private var bikeStore = BikeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recorder)
                .environmentObject(recorder.store)
                .environmentObject(bikeStore)
        }
    }
}
