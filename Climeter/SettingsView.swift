import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var profileManager: ProfileManager
    @State private var editingProfileID: UUID?
    @State private var editingName: String = ""
    @State private var launchAtLogin: Bool = LaunchAtLoginService.isEnabled
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        Form {
            Section("Profiles") {
                List {
                    ForEach(profileManager.profiles) { profile in
                        HStack {
                            if editingProfileID == profile.id {
                                TextField("Profile name", text: $editingName, onCommit: {
                                    commitRename()
                                })
                                .textFieldStyle(.roundedBorder)
                            } else {
                                Text(profile.name)
                                    .fontWeight(profileManager.activeProfile?.id == profile.id ? .semibold : .regular)
                                    .foregroundColor(profileManager.activeProfile?.id == profile.id ? .primary : .secondary)
                            }

                            Spacer()

                            if editingProfileID == profile.id {
                                Button("Done") {
                                    commitRename()
                                }
                                .buttonStyle(.borderless)
                            } else {
                                Button(action: {
                                    startEditing(profile: profile)
                                }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Rename profile")
                            }

                            Button(action: {
                                profileManager.deleteProfile(id: profile.id)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Delete profile")
                            .disabled(profileManager.profiles.count <= 1)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if editingProfileID == nil {
                                profileManager.switchProfile(to: profile.id)
                            }
                        }
                    }
                }
                .frame(minHeight: 120)

                Button("Add Profile") {
                    profileManager.createProfile(name: "New Profile")
                }
            }

            Section("CLI Account") {
                HStack {
                    Text("Status:")
                    Spacer()
                    Text(profileManager.isAuthenticated ? "Connected" : "Not Connected")
                        .foregroundColor(profileManager.isAuthenticated ? .green : .secondary)
                }

                HStack {
                    Button("Resync") {
                        profileManager.syncCLICredentials()
                    }
                    .help("Re-read CLI credentials from system Keychain")

                    Button("Remove") {
                        profileManager.removeCredential()
                    }
                    .help("Delete credential for active profile")
                    .disabled(!profileManager.isAuthenticated)
                }
            }

            Section("Settings") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            try LaunchAtLoginService.toggle()
                        } catch {
                            launchAtLogin = !newValue
                            errorMessage = "Failed to toggle Launch at Login: \(error.localizedDescription)"
                            showError = true
                        }
                    }

                if let activeProfile = profileManager.activeProfile {
                    Toggle("Auto-start Session", isOn: Binding(
                        get: { activeProfile.autoStartSession },
                        set: { newValue in
                            profileManager.updateAutoStartSession(id: activeProfile.id, enabled: newValue)
                        }
                    ))
                    .help("Automatically start usage tracking when app launches")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func startEditing(profile: Profile) {
        editingProfileID = profile.id
        editingName = profile.name
    }

    private func commitRename() {
        guard let id = editingProfileID else { return }
        profileManager.renameProfile(id: id, name: editingName)
        editingProfileID = nil
        editingName = ""
    }
}

#Preview {
    SettingsView(profileManager: ProfileManager())
}
