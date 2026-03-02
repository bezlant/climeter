import SwiftUI

@main
struct ClimeterApp: App {
    @StateObject private var profileManager = ProfileManager()

    var body: some Scene {
        MenuBarExtra("42%") {
            PopoverView(profileManager: profileManager)
        }
        .menuBarExtraStyle(.window)
    }
}
