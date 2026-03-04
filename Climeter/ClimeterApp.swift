import SwiftUI

@main
struct ClimeterApp: App {
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        MenuBarExtra(menuBarTitle) {
            PopoverView(profileManager: profileManager, updateChecker: updateChecker)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(profileManager: profileManager)
        }
        .windowResizability(.contentSize)
    }

    private var menuBarTitle: String {
        guard let usageData = profileManager.cliActiveUsageData else {
            return "—"
        }
        let utilization = usageData.fiveHour.utilization
        let percentage = "\(Int(utilization.rounded()))%"

        if profileManager.profiles.count > 1, let name = profileManager.cliActiveProfile?.name {
            return "\(name): \(percentage)"
        }
        return percentage
    }
}
