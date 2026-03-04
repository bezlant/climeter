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
                                TextField("Profile name", text: $editingName)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit { commitRename() }
                            } else {
                                Text(profile.name)
                                    .fontWeight(profileManager.cliActiveProfileID == profile.id ? .semibold : .regular)
                                    .foregroundColor(profileManager.cliActiveProfileID == profile.id ? .primary : .secondary)
                            }

                            if profileManager.cliActiveProfileID == profile.id {
                                Image(systemName: "terminal")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                    .help("CLI-active account")
                            }

                            Spacer()

                            if editingProfileID == profile.id {
                                Button("Done") { commitRename() }
                                    .buttonStyle(.borderless)
                            } else {
                                if ProfileStore.loadCredentialModel(for: profile.id) != nil,
                                   profileManager.cliActiveProfileID != profile.id {
                                    Button("Activate for CLI") {
                                        profileManager.activateForCLI(profileID: profile.id)
                                    }
                                    .controlSize(.small)
                                    .buttonStyle(.bordered)
                                }

                                Button(action: { startEditing(profile: profile) }) {
                                    Image(systemName: "pencil")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.borderless)
                                .help("Rename profile")
                            }

                            Button(action: { profileManager.deleteProfile(id: profile.id) }) {
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
                            if editingProfileID != nil {
                                editingProfileID = nil
                                editingName = ""
                            }
                        }
                    }
                }
                .frame(minHeight: 120)

                Button("Add Profile") {
                    profileManager.createProfile(name: "New Profile")
                }
            }

            Section("CLI Sync") {
                HStack {
                    Text("Active CLI Account:")
                    Spacer()
                    if let name = profileManager.cliActiveProfile?.name {
                        Text(name)
                            .foregroundColor(.green)
                    } else {
                        Text("None")
                            .foregroundColor(.secondary)
                    }
                }

                Text("Climeter detects /login automatically and syncs credentials.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
