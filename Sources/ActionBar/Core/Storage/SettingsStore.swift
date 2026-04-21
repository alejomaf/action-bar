import Foundation

struct SettingsStore {
    private enum Keys {
        static let gitHubOAuthClientID = "gitHubOAuthClientID"
    }

    private enum Defaults {
        static let bundledGitHubOAuthClientID = "Ov23lixkwTAIlYy2wLsN"
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

        if let environmentValue = environment["ACTION_BAR_GITHUB_CLIENT_ID"],
           !environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return environmentValue
        }

        return Defaults.bundledGitHubOAuthClientID
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
