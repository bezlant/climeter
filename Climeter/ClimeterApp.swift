import SwiftUI

@main
struct ClimeterApp: App {
    var body: some Scene {
        MenuBarExtra("42%") {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
