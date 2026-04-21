import Foundation

actor RunPoller {
    func refresh(using client: GitHubClient, repositories: [Repository]) async throws -> WorkflowSnapshot {
        try await client.fetchRecentRuns(for: repositories)
    }

    func interval(for summary: ActivitySummary) -> Duration {
        summary.activeRunCount > 0 ? .seconds(15) : .seconds(60)
    }
}
