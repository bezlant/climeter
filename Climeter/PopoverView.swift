import SwiftUI

struct PopoverView: View {
    @ObservedObject var profileManager: ProfileManager

    var body: some View {
        VStack(spacing: 16) {
            Text("Climeter")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(spacing: 8) {
                if let profile = profileManager.activeProfile {
                    Text(profile.name)
                        .font(.headline)
                }

                Text(profileManager.isAuthenticated ? "Authenticated" : "Not Connected")
                    .font(.subheadline)
                    .foregroundColor(profileManager.isAuthenticated ? .green : .secondary)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(width: 200)
    }
}

#Preview {
    PopoverView(profileManager: ProfileManager())
}
