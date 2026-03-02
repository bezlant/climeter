import SwiftUI

@main
struct ClimeterApp: App {
    var body: some Scene {
        MenuBarExtra("Climeter", systemImage: "chart.bar.fill") {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
