import Foundation

struct RepositoryRegistry {
    private enum Keys {
        static let repositories = "trackedRepositories"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [Repository] {
        guard let data = defaults.data(forKey: Keys.repositories),
              let repositories = try? decoder.decode([Repository].self, from: data) else {
            return []
        }

        return repositories
    }

    func save(_ repositories: [Repository]) {
        guard let data = try? encoder.encode(repositories) else {
            return
        }

        defaults.set(data, forKey: Keys.repositories)
    }
}
