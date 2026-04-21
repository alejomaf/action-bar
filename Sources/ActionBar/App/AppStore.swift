import Foundation
import Observation

@MainActor
@Observable
final class AppStore {
    enum DataMode: String {
        case preview
        case live
    }

    var repositories: [Repository]
    var runGroups: [RepositoryRunGroup]
    var isRefreshing = false
    var lastRefresh: Date?
    var rateLimit: GitHubRateLimit?
    var errorMessage: String?
    var dataMode: DataMode

    var summary: ActivitySummary {
        ActivitySummary(groups: runGroups)
    }

    private let repositoryRegistry: RepositoryRegistry
    private let client: GitHubClient
    private let poller: RunPoller

    init(
        repositoryRegistry: RepositoryRegistry = RepositoryRegistry(),
        client: GitHubClient = GitHubClient(mode: .preview),
        poller: RunPoller = RunPoller()
    ) {
        self.repositoryRegistry = repositoryRegistry
        self.client = client
        self.poller = poller

        let persistedRepositories = repositoryRegistry.load()
        repositories = persistedRepositories.isEmpty ? Repository.previewDefaults : persistedRepositories
        runGroups = []
        dataMode = .preview

        Task {
            await refresh()
        }
    }

    func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        errorMessage = nil

        do {
            let snapshot = try await poller.refresh(using: client, repositories: repositories)
            apply(snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    func addRepository(from input: String) throws {
        let repository = try Repository(validating: input)

        guard !repositories.contains(where: { $0.id == repository.id }) else {
            return
        }

        repositories.append(repository)
        repositories.sort { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        repositoryRegistry.save(repositories)

        Task {
            await refresh()
        }
    }

    func removeRepository(_ repository: Repository) {
        repositories.removeAll { $0.id == repository.id }
        repositoryRegistry.save(repositories)
        runGroups.removeAll { $0.repository == repository }

        Task {
            await refresh()
        }
    }

    func restorePreviewRepositories() {
        repositories = Repository.previewDefaults
        repositoryRegistry.save(repositories)

        Task {
            await refresh()
        }
    }

    private func apply(_ snapshot: WorkflowSnapshot) {
        runGroups = snapshot.groups
            .filter { repositories.contains($0.repository) }
            .sorted { lhs, rhs in
                let lhsDate = lhs.runs.first?.sortDate ?? .distantPast
                let rhsDate = rhs.runs.first?.sortDate ?? .distantPast
                return lhsDate > rhsDate
            }
        lastRefresh = snapshot.fetchedAt
        rateLimit = snapshot.rateLimit
        dataMode = snapshot.dataMode
    }
}
