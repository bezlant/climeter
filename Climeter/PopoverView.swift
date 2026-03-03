import SwiftUI

struct PopoverView: View {
    @ObservedObject var profileManager: ProfileManager
    @State private var currentTime = Date.now

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header with title and refresh button
            HStack {
                Text("Climeter")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if profileManager.isAuthenticated {
                    Button(action: {
                        profileManager.refresh()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh usage data")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Content area
            VStack(spacing: 0) {
                if !profileManager.isAuthenticated {
                    // Not connected state
                    Text("Not Connected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 32)
                } else if let usageData = profileManager.usageData {
                    // Usage cards
                    UsageCard(
                        label: "Session",
                        window: usageData.fiveHour,
                        currentTime: currentTime
                    )
                    .padding(.top, 16)
                    .padding(.horizontal, 20)

                    Divider()
                        .padding(.vertical, 12)

                    UsageCard(
                        label: "Week",
                        window: usageData.sevenDay,
                        currentTime: currentTime
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                } else {
                    // Loading state
                    Text("Loading...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 32)
                }
            }

            Divider()

            // Quit button
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 240)
        .onReceive(timer) { time in
            currentTime = time
        }
    }
}

struct UsageCard: View {
    let label: String
    let window: UsageWindow
    let currentTime: Date

    private var percentage: String {
        String(format: "%.0f%%", window.utilization)
    }

    private var progressValue: Double {
        window.utilization / 100.0
    }

    private var progressColor: Color {
        if window.utilization >= 80 {
            return .red
        } else if window.utilization >= 60 {
            return .yellow
        } else {
            return .green
        }
    }

    private var countdown: String {
        let interval = window.resetsAt.timeIntervalSince(currentTime)

        guard interval > 0 else {
            return "Resetting..."
        }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let days = hours / 24
        let remainingHours = hours % 24

        if days > 0 {
            return "Resets in \(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "Resets in \(hours)h \(minutes)m"
        } else {
            return "Resets in \(minutes)m"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label and percentage
            HStack {
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(percentage)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(progressColor)
            }

            // Progress bar
            ProgressView(value: progressValue)
                .tint(progressColor)
                .frame(height: 8)

            // Countdown
            Text(countdown)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    PopoverView(profileManager: ProfileManager())
}
