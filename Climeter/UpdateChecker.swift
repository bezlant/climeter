import Foundation

class UpdateChecker: ObservableObject {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String?
    var releaseURL: String?

    private let lastCheckKey = "lastUpdateCheckDate"
    private let dismissedVersionKey = "dismissedUpdateVersion"
    private var dailyTimer: Timer?

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
    }

    init() {
        let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(lastCheck) > 86400 {
            checkForUpdates()
        }
        dailyTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
            self?.checkForUpdates()
        }
    }

    func checkForUpdates() {
        let urlString = "https://api.github.com/repos/bezlant/cliMeter/releases/latest"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String,
                      let htmlURL = json["html_url"] as? String else { return }

                let remote = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

                if remote.compare(currentVersion, options: .numeric) == .orderedDescending {
                    let dismissed = UserDefaults.standard.string(forKey: dismissedVersionKey)
                    if dismissed != remote {
                        latestVersion = remote
                        releaseURL = htmlURL
                        updateAvailable = true
                    }
                }

                UserDefaults.standard.set(Date(), forKey: lastCheckKey)
            } catch {
                // Silent failure
            }
        }
    }

    func dismissUpdate() {
        if let version = latestVersion {
            UserDefaults.standard.set(version, forKey: dismissedVersionKey)
        }
        updateAvailable = false
        latestVersion = nil
        releaseURL = nil
    }

    deinit {
        dailyTimer?.invalidate()
    }
}
