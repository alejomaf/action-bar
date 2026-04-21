import Foundation

struct GitHubRateLimit: Equatable, Sendable {
    let remaining: Int
    let limit: Int
    let resetAt: Date
}

struct WorkflowSnapshot: Sendable {
    let groups: [RepositoryRunGroup]
    let fetchedAt: Date
    let rateLimit: GitHubRateLimit?
    let dataMode: AppStore.DataMode
}

enum GitHubClientError: LocalizedError, Sendable {
    case missingAuthentication
    case invalidResponse
    case unexpectedStatusCode(Int)

    var errorDescription: String? {
        switch self {
        case .missingAuthentication:
            return "Sign in to GitHub to load your repositories."
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        case let .unexpectedStatusCode(statusCode):
            return "GitHub returned HTTP \(statusCode)."
        }
    }
}

actor GitHubClient {
    private enum Constants {
        static let perRepositoryLimit = 10
    }

    private let authService: GitHubAuthService
    private let session: URLSession
    private let jsonDecoder: JSONDecoder

    init(
        authService: GitHubAuthService = GitHubAuthService(),
        session: URLSession = .shared
    ) {
        self.authService = authService
        self.session = session

        jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        jsonDecoder.dateDecodingStrategy = .iso8601
    }

    func fetchRecentRuns(for repositories: [Repository]) async throws -> WorkflowSnapshot {
        guard let authSession = try await authService.loadSession() else {
            try await Task.sleep(for: .milliseconds(120))
            return .preview(for: repositories)
        }

        let now = Date.now
        var groups: [RepositoryRunGroup] = []
        var rateLimit: GitHubRateLimit?

        for repository in repositories {
            let response = try await fetchWorkflowRuns(
                for: repository,
                accessToken: authSession.accessToken,
                limit: Constants.perRepositoryLimit
            )

            groups.append(RepositoryRunGroup(repository: repository, runs: response.runs))
            rateLimit = rateLimit?.merged(with: response.rateLimit) ?? response.rateLimit
        }

        return WorkflowSnapshot(
            groups: groups,
            fetchedAt: now,
            rateLimit: rateLimit,
            dataMode: .live
        )
    }

    private func fetchWorkflowRuns(
        for repository: Repository,
        accessToken: String,
        limit: Int
    ) async throws -> RepositoryRunsResponse {
        guard let url = workflowRunsURL(for: repository, limit: limit) else {
            throw GitHubClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            let payload = try jsonDecoder.decode(WorkflowRunsPayload.self, from: data)
            return RepositoryRunsResponse(
                runs: payload.workflowRuns.map { $0.workflowRun(repository: repository) },
                rateLimit: GitHubRateLimit(response: httpResponse)
            )
        case 401:
            try? await authService.signOut()
            throw GitHubAuthError.invalidToken
        case 404:
            return RepositoryRunsResponse(runs: [], rateLimit: GitHubRateLimit(response: httpResponse))
        default:
            throw GitHubClientError.unexpectedStatusCode(httpResponse.statusCode)
        }
    }

    private func workflowRunsURL(for repository: Repository, limit: Int) -> URL? {
        let owner = repository.owner.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repository.owner
        let name = repository.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repository.name

        var components = URLComponents(string: "https://api.github.com/repos/\(owner)/\(name)/actions/runs")
        components?.queryItems = [
            URLQueryItem(name: "per_page", value: String(limit)),
        ]

        return components?.url
    }
}

private struct RepositoryRunsResponse: Sendable {
    let runs: [WorkflowRun]
    let rateLimit: GitHubRateLimit?
}

private struct WorkflowRunsPayload: Decodable {
    let workflowRuns: [WorkflowRunPayload]
}

private struct WorkflowRunPayload: Decodable {
    let id: Int
    let name: String?
    let displayTitle: String?
    let headBranch: String?
    let status: String
    let conclusion: String?
    let htmlUrl: URL
    let createdAt: Date
    let updatedAt: Date
    let actor: ActorPayload?

    func workflowRun(repository: Repository) -> WorkflowRun {
        WorkflowRun(
            id: String(id),
            name: resolvedName,
            branch: headBranch ?? "unknown",
            actor: actor?.login ?? repository.owner,
            status: mappedStatus,
            conclusion: mappedConclusion,
            htmlURL: htmlUrl,
            logsURL: nil,
            startedAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private var resolvedName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }

        let trimmedTitle = displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedTitle, !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        return "Workflow"
    }

    private var mappedStatus: WorkflowRunStatus {
        switch status {
        case WorkflowRunStatus.inProgress.rawValue:
            return .inProgress
        case WorkflowRunStatus.completed.rawValue:
            return .completed
        case "queued", "requested", "waiting", "pending":
            return .queued
        default:
            return .queued
        }
    }

    private var mappedConclusion: WorkflowRunConclusion? {
        switch conclusion {
        case WorkflowRunConclusion.success.rawValue:
            return .success
        case WorkflowRunConclusion.failure.rawValue, "startup_failure":
            return .failure
        case WorkflowRunConclusion.cancelled.rawValue:
            return .cancelled
        case WorkflowRunConclusion.neutral.rawValue, "stale":
            return .neutral
        case WorkflowRunConclusion.skipped.rawValue:
            return .skipped
        case WorkflowRunConclusion.timedOut.rawValue:
            return .timedOut
        case WorkflowRunConclusion.actionRequired.rawValue:
            return .actionRequired
        case .none:
            return nil
        default:
            return .neutral
        }
    }
}

private struct ActorPayload: Decodable {
    let login: String
}

private extension GitHubRateLimit {
    init?(response: HTTPURLResponse) {
        guard let remainingValue = response.value(forHTTPHeaderField: "x-ratelimit-remaining"),
              let remaining = Int(remainingValue),
              let limitValue = response.value(forHTTPHeaderField: "x-ratelimit-limit"),
              let limit = Int(limitValue),
              let resetValue = response.value(forHTTPHeaderField: "x-ratelimit-reset"),
              let resetTimestamp = TimeInterval(resetValue) else {
            return nil
        }

        self.init(
            remaining: remaining,
            limit: limit,
            resetAt: Date(timeIntervalSince1970: resetTimestamp)
        )
    }

    func merged(with other: GitHubRateLimit?) -> GitHubRateLimit {
        guard let other else {
            return self
        }

        return GitHubRateLimit(
            remaining: min(remaining, other.remaining),
            limit: max(limit, other.limit),
            resetAt: min(resetAt, other.resetAt)
        )
    }
}

extension WorkflowSnapshot {
    static func preview(for repositories: [Repository], now: Date = .now) -> WorkflowSnapshot {
        let groups = repositories.enumerated().map { index, repository in
            RepositoryRunGroup(repository: repository, runs: previewRuns(for: repository, index: index, now: now))
        }

        return WorkflowSnapshot(
            groups: groups,
            fetchedAt: now,
            rateLimit: GitHubRateLimit(remaining: 4_982, limit: 5_000, resetAt: now.addingTimeInterval(47 * 60)),
            dataMode: .preview
        )
    }

    private static func previewRuns(for repository: Repository, index: Int, now: Date) -> [WorkflowRun] {
        switch index % 3 {
        case 0:
            return [
                WorkflowRun(
                    id: "\(repository.id)-ci-running",
                    name: "CI",
                    branch: "main",
                    actor: "alex",
                    status: .inProgress,
                    conclusion: nil,
                    htmlURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/1001")!,
                    logsURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/1001/job/1")!,
                    startedAt: now.addingTimeInterval(-4 * 60 - 18),
                    updatedAt: now.addingTimeInterval(-25)
                ),
                WorkflowRun(
                    id: "\(repository.id)-deploy-success",
                    name: "Deploy",
                    branch: "main",
                    actor: "alex",
                    status: .completed,
                    conclusion: .success,
                    htmlURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/1000")!,
                    logsURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/1000/job/1")!,
                    startedAt: now.addingTimeInterval(-17 * 60),
                    updatedAt: now.addingTimeInterval(-11 * 60)
                ),
            ]
        case 1:
            return [
                WorkflowRun(
                    id: "\(repository.id)-release-queued",
                    name: "Release",
                    branch: "release/1.0",
                    actor: "sam",
                    status: .queued,
                    conclusion: nil,
                    htmlURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/2001")!,
                    logsURL: nil,
                    startedAt: now.addingTimeInterval(-95),
                    updatedAt: now.addingTimeInterval(-30)
                ),
                WorkflowRun(
                    id: "\(repository.id)-tests-success",
                    name: "Tests",
                    branch: "feature/menu-bar-shell",
                    actor: "sam",
                    status: .completed,
                    conclusion: .success,
                    htmlURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/2000")!,
                    logsURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/2000/job/1")!,
                    startedAt: now.addingTimeInterval(-45 * 60),
                    updatedAt: now.addingTimeInterval(-31 * 60)
                ),
            ]
        default:
            return [
                WorkflowRun(
                    id: "\(repository.id)-tests-failure",
                    name: "Tests",
                    branch: "feature/notifications",
                    actor: "casey",
                    status: .completed,
                    conclusion: .failure,
                    htmlURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/3001")!,
                    logsURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/3001/job/1")!,
                    startedAt: now.addingTimeInterval(-24 * 60),
                    updatedAt: now.addingTimeInterval(-7 * 60)
                ),
                WorkflowRun(
                    id: "\(repository.id)-lint-success",
                    name: "Lint",
                    branch: "main",
                    actor: "casey",
                    status: .completed,
                    conclusion: .success,
                    htmlURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/3000")!,
                    logsURL: URL(string: "https://github.com/\(repository.fullName)/actions/runs/3000/job/1")!,
                    startedAt: now.addingTimeInterval(-65 * 60),
                    updatedAt: now.addingTimeInterval(-62 * 60)
                ),
            ]
        }
    }
}
