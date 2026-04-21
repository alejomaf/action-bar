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
    var gitHubOAuthClientID: String
    var authenticatedAccount: GitHubAccount?
    var activeDeviceAuthorization: GitHubDeviceAuthorization?
    var isAuthenticating = false
    var authErrorMessage: String?
    var authStatusMessage: String?

    var summary: ActivitySummary {
        ActivitySummary(groups: runGroups)
    }

    var isSignedInToGitHub: Bool {
        authenticatedAccount != nil
    }

    var hasOAuthClientID: Bool {
        !gitHubOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let repositoryRegistry: RepositoryRegistry
    private let settingsStore: SettingsStore
    private let authService: GitHubAuthService
    private let client: GitHubClient
    private let poller: RunPoller
    private var signInTask: Task<Void, Never>?

    init(
        repositoryRegistry: RepositoryRegistry = RepositoryRegistry(),
        settingsStore: SettingsStore = SettingsStore(),
        authService: GitHubAuthService = GitHubAuthService(),
        client: GitHubClient? = nil,
        poller: RunPoller = RunPoller()
    ) {
        self.repositoryRegistry = repositoryRegistry
        self.settingsStore = settingsStore
        self.authService = authService
        self.client = client ?? GitHubClient(authService: authService)
        self.poller = poller

        let persistedRepositories = repositoryRegistry.load()
        repositories = persistedRepositories.isEmpty ? Repository.previewDefaults : persistedRepositories
        runGroups = []
        dataMode = .preview
        gitHubOAuthClientID = settingsStore.loadGitHubOAuthClientID()

        Task {
            await restoreAuthenticationState()
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
            if let authError = error as? GitHubAuthError,
               authError == .invalidToken {
                try? await authService.signOut()
                authenticatedAccount = nil
                authErrorMessage = authError.localizedDescription
                apply(.preview(for: repositories))
            }

            errorMessage = error.localizedDescription
        }

        isRefreshing = false
    }

    func updateGitHubOAuthClientID(_ clientID: String) {
        gitHubOAuthClientID = clientID
        settingsStore.saveGitHubOAuthClientID(clientID)
    }

    func startGitHubDeviceFlow() {
        let clientID = gitHubOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            authErrorMessage = GitHubAuthError.missingClientID.localizedDescription
            return
        }

        signInTask?.cancel()
        authErrorMessage = nil
        authStatusMessage = "Requesting a GitHub device code..."
        activeDeviceAuthorization = nil
        isAuthenticating = true

        signInTask = Task {
            do {
                let authorization = try await authService.startDeviceAuthorization(clientID: clientID)

                await MainActor.run {
                    self.activeDeviceAuthorization = authorization
                    self.authStatusMessage = "Open GitHub, enter the code, and authorize Action Bar."
                }

                let authSession = try await authService.awaitAccessToken(clientID: clientID, authorization: authorization)
                let account = try await authService.fetchAuthenticatedAccount(accessToken: authSession.accessToken)

                await MainActor.run {
                    self.authenticatedAccount = account
                    self.activeDeviceAuthorization = nil
                    self.isAuthenticating = false
                    self.authErrorMessage = nil
                    self.authStatusMessage = "Signed in as \(account.login)."
                    Task {
                        await self.refresh()
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.activeDeviceAuthorization = nil
                    self.isAuthenticating = false
                    self.authStatusMessage = "GitHub sign-in canceled."
                }
            } catch {
                await MainActor.run {
                    self.activeDeviceAuthorization = nil
                    self.isAuthenticating = false
                    self.authErrorMessage = error.localizedDescription
                    self.authStatusMessage = nil
                }
            }
        }
    }

    func cancelGitHubDeviceFlow() {
        signInTask?.cancel()
    }

    func signOutFromGitHub() {
        signInTask?.cancel()

        Task {
            try? await authService.signOut()
        }

        authenticatedAccount = nil
        activeDeviceAuthorization = nil
        isAuthenticating = false
        authErrorMessage = nil
        authStatusMessage = "Signed out."

        Task {
            await refresh()
        }
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

    private func restoreAuthenticationState() async {
        do {
            guard let session = try await authService.loadSession() else {
                authStatusMessage = "Add a GitHub OAuth Client ID to enable sign-in."
                return
            }

            let account = try await authService.fetchAuthenticatedAccount(accessToken: session.accessToken)
            authenticatedAccount = account
            authStatusMessage = "Signed in as \(account.login)."
        } catch {
            try? await authService.signOut()
            authenticatedAccount = nil
            authErrorMessage = error.localizedDescription
        }
    }
}
