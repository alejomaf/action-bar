import Foundation
import Testing
@testable import ActionBar

@Test
func summaryCountsQueuedRunningAndFailedRuns() {
    let now = Date(timeIntervalSince1970: 1_718_000_000)
    let repository = Repository(owner: "owner", name: "repo")
    let groups = [
        RepositoryRunGroup(
            repository: repository,
            runs: [
                WorkflowRun(
                    id: "running",
                    name: "CI",
                    branch: "main",
                    actor: "alex",
                    status: .inProgress,
                    conclusion: nil,
                    htmlURL: URL(string: "https://example.com/running")!,
                    logsURL: nil,
                    startedAt: now.addingTimeInterval(-120),
                    updatedAt: now.addingTimeInterval(-20)
                ),
                WorkflowRun(
                    id: "queued",
                    name: "Deploy",
                    branch: "main",
                    actor: "alex",
                    status: .queued,
                    conclusion: nil,
                    htmlURL: URL(string: "https://example.com/queued")!,
                    logsURL: nil,
                    startedAt: now.addingTimeInterval(-30),
                    updatedAt: now.addingTimeInterval(-15)
                ),
                WorkflowRun(
                    id: "failed",
                    name: "Tests",
                    branch: "feature/x",
                    actor: "alex",
                    status: .completed,
                    conclusion: .failure,
                    htmlURL: URL(string: "https://example.com/failed")!,
                    logsURL: nil,
                    startedAt: now.addingTimeInterval(-600),
                    updatedAt: now.addingTimeInterval(-60)
                ),
            ]
        ),
    ]

    let summary = ActivitySummary(groups: groups, referenceDate: now)

    #expect(summary.runningCount == 1)
    #expect(summary.queuedCount == 1)
    #expect(summary.recentFailureCount == 1)
    #expect(summary.activeRunCount == 2)
    #expect(summary.symbolName == "exclamationmark.circle.fill")
}

@Test
func repositoryParserRequiresOwnerAndName() throws {
    let repository = try Repository(validating: "owner/repo")

    #expect(repository.owner == "owner")
    #expect(repository.name == "repo")
    #expect(throws: RepositoryInputError.invalidFullName) {
        try Repository(validating: "owner-only")
    }
}
