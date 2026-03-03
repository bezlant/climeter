import SwiftUI

@main
struct ClimeterApp: App {
    @StateObject private var profileManager = ProfileManager()

    var body: some Scene {
        MenuBarExtra(menuBarTitle) {
            PopoverView(profileManager: profileManager)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(profileManager: profileManager)
        }
        .windowResizability(.contentSize)
    }

    private var menuBarTitle: String {
        guard let utilization = profileManager.usageData?.fiveHour.utilization else {
            return "—"
        }
        return "\(Int(utilization.rounded()))%"
    }
}
