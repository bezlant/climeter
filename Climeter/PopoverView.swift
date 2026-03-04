import SwiftUI

struct PopoverView: View {
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var updateChecker: UpdateChecker
    @State private var currentTime = Date.now
    @Environment(\.openWindow) private var openWindow

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Climeter")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Button(action: { openWindow(id: "settings") }) {
                    Image(systemName: "gear")
                        .imageScale(.medium)
                }
                .buttonStyle(.borderless)
                .help("Settings")

                if profileManager.hasAnyAuthenticated {
                    Button(action: { profileManager.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh all accounts")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Update banner
            if updateChecker.updateAvailable, let version = updateChecker.latestVersion {
                HStack(spacing: 4) {
                    if let urlString = updateChecker.releaseURL,
                       let url = URL(string: urlString) {
                        Link("v\(version) available", destination: url)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("v\(version) available")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { updateChecker.dismissUpdate() }) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)

                Divider()
            }

            // Content
            if authenticatedProfiles.isEmpty {
                Text("Run /login in Claude Code\nto connect an account")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 32)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(authenticatedProfiles.enumerated()), id: \.element.id) { index, profile in
                            if index > 0 {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                            ProfileCard(
                                profile: profile,
                                usageData: profileManager.allUsageData[profile.id],
                                errorMessage: profileManager.allErrors[profile.id],
                                isCLIActive: profileManager.cliActiveProfileID == profile.id,
                                showProfileName: authenticatedProfiles.count > 1,
                                currentTime: currentTime,
                                onActivate: {
                                    profileManager.activateForCLI(profileID: profile.id)
                                }
                            )
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            Divider()

            // Quit
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(width: 280)
        .onReceive(timer) { time in
            currentTime = time
        }
    }

    private var authenticatedProfiles: [Profile] {
        profileManager.profiles.filter { profile in
            ProfileStore.loadCredentialModel(for: profile.id) != nil
        }
    }
}

// MARK: - Profile Card

struct ProfileCard: View {
    let profile: Profile
    let usageData: UsageData?
    let errorMessage: String?
    let isCLIActive: Bool
    let showProfileName: Bool
    let currentTime: Date
    let onActivate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Profile header with name and action
            if showProfileName {
                HStack {
                    Text(profile.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if isCLIActive {
                        CLIBadge()
                    }

                    Spacer()

                    if !isCLIActive {
                        Button("Use") { onActivate() }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                    }
                }
            }

            // Usage data
            if let data = usageData {
                CompactUsageRow(
                    label: "Session",
                    window: data.fiveHour,
                    currentTime: currentTime
                )
                CompactUsageRow(
                    label: "Week",
                    window: data.sevenDay,
                    currentTime: currentTime
                )
            } else if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else {
                Text("Loading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - CLI Badge

struct CLIBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
            Text("CLI")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.green.opacity(0.15))
        .cornerRadius(4)
    }
}

// MARK: - Compact Usage Row

struct CompactUsageRow: View {
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
        if window.utilization >= 80 { return .red }
        else if window.utilization >= 60 { return .yellow }
        else { return .green }
    }

    private var countdown: String {
        let interval = window.resetsAt.timeIntervalSince(currentTime)
        guard interval > 0 else { return "Resetting..." }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let days = hours / 24
        let remainingHours = hours % 24

        if days > 0 {
            return "\(days)d \(remainingHours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text(percentage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(progressColor)
                Text("·")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(countdown)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: progressValue)
                .tint(progressColor)
                .frame(height: 6)
        }
    }
}

#Preview {
    PopoverView(profileManager: ProfileManager(), updateChecker: UpdateChecker())
}
