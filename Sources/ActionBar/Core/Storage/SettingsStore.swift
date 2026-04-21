import Foundation

struct SettingsStore {
    private enum Keys {
        static let gitHubOAuthClientID = "gitHubOAuthClientID"
    }

    private let defaults: UserDefaults
    private let environment: [String: String]

    init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.environment = environment
    }

    func loadGitHubOAuthClientID() -> String {
        if let storedValue = defaults.string(forKey: Keys.gitHubOAuthClientID),
           !storedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedValue
        }

        return environment["ACTION_BAR_GITHUB_CLIENT_ID"] ?? ""
    }

    func saveGitHubOAuthClientID(_ clientID: String) {
        let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            defaults.removeObject(forKey: Keys.gitHubOAuthClientID)
        } else {
            defaults.set(trimmed, forKey: Keys.gitHubOAuthClientID)
        }
    }
}
