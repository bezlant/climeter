import SwiftUI

@main
struct ClimeterApp: App {
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(profileManager: profileManager, updateChecker: updateChecker)
        } label: {
            if let usageData = profileManager.cliActiveUsageData {
                let utilization = usageData.fiveHour.utilization
                Image(nsImage: MenuBarIcon.progressBar(utilization: utilization))
            } else {
                Text("—")
            }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView(profileManager: profileManager)
        }
        .windowResizability(.contentSize)
    }
}
