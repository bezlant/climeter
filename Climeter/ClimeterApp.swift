import SwiftUI

@main
struct ClimeterApp: App {
    @StateObject private var profileManager = ProfileManager()
    @StateObject private var updateChecker = UpdateChecker()

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.bezlant.climeter"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != .current }
        if let existing = others.first {
            NSLog("Another Climeter already running (PID %d) — exiting", existing.processIdentifier)
            existing.activate()
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(profileManager: profileManager, updateChecker: updateChecker)
        } label: {
            if let usageData = profileManager.cliActiveUsageData {
                let utilization = usageData.fiveHour.utilization
                let isPeak = profileManager.peakHoursEnabled && PeakHoursService.isPeakNow()
                Image(nsImage: MenuBarIcon.progressBar(utilization: utilization, isPeak: isPeak))
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
