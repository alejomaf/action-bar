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
    case liveModeUnavailable

    var errorDescription: String? {
        switch self {
        case .missingAuthentication:
            return "Sign in to GitHub to load your repositories."
        case .liveModeUnavailable:
            return "Live GitHub syncing has not been wired yet."
        }
    }
}

actor GitHubClient {
    enum Mode: Sendable {
        case preview
        case live
    }

    private let mode: Mode

    init(mode: Mode) {
        self.mode = mode
    }

    func fetchRecentRuns(for repositories: [Repository]) async throws -> WorkflowSnapshot {
        switch mode {
        case .preview:
            try await Task.sleep(for: .milliseconds(120))
            return .preview(for: repositories)
        case .live:
            throw GitHubClientError.liveModeUnavailable
        }
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
