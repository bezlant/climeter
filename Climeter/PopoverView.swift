import SwiftUI

struct PopoverView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Climeter")
                .font(.title2)
                .fontWeight(.semibold)

            Text("42%")
                .font(.system(size: 48, weight: .bold))

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
    PopoverView()
}
