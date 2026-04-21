import Foundation

enum WorkflowRunStatus: String, Codable, Sendable {
    case queued
    case inProgress = "in_progress"
    case completed
}

enum WorkflowRunConclusion: String, Codable, Sendable {
    case success
    case failure
    case cancelled
    case neutral
    case skipped
    case timedOut = "timed_out"
    case actionRequired = "action_required"
}

enum WorkflowDisplayState: Sendable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
    case neutral

    var symbolName: String {
        switch self {
        case .queued:
            return "clock.fill"
        case .running:
            return "bolt.circle.fill"
        case .succeeded:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .cancelled:
            return "minus.circle.fill"
        case .neutral:
            return "circle.dashed"
        }
    }
}

struct WorkflowRun: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let branch: String
    let actor: String
    let status: WorkflowRunStatus
    let conclusion: WorkflowRunConclusion?
    let htmlURL: URL
    let logsURL: URL?
    let startedAt: Date
    let updatedAt: Date

    var displayState: WorkflowDisplayState {
        switch status {
        case .queued:
            return .queued
        case .inProgress:
            return .running
        case .completed:
            switch conclusion {
            case .success:
                return .succeeded
            case .failure:
                return .failed
            case .cancelled:
                return .cancelled
            case .none, .neutral, .skipped, .timedOut, .actionRequired:
                return .neutral
            }
        }
    }

    var isActive: Bool {
        status == .queued || status == .inProgress
    }

    var isRecentFailure: Bool {
        displayState == .failed && updatedAt > .now.addingTimeInterval(-30 * 60)
    }

    var sortDate: Date {
        max(startedAt, updatedAt)
    }

    func relativeTimestamp(referenceDate: Date = .now) -> String {
        switch status {
        case .queued:
            return "Queued \(startedAt.relativeDescription(referenceDate: referenceDate))"
        case .inProgress:
            return startedAt.elapsedDescription(referenceDate: referenceDate)
        case .completed:
            return updatedAt.relativeDescription(referenceDate: referenceDate)
        }
    }
}

struct RepositoryRunGroup: Identifiable, Hashable, Sendable {
    let repository: Repository
    let runs: [WorkflowRun]

    var id: String {
        repository.id
    }

    var hasActivity: Bool {
        !runs.isEmpty
    }
}

struct ActivitySummary: Sendable {
    let runningCount: Int
    let queuedCount: Int
    let recentFailureCount: Int
    let recentlyCompletedCount: Int

    init(groups: [RepositoryRunGroup], referenceDate: Date = .now) {
        let allRuns = groups.flatMap(\.runs)
        runningCount = allRuns.filter { $0.status == .inProgress }.count
        queuedCount = allRuns.filter { $0.status == .queued }.count
        recentFailureCount = allRuns.filter { $0.displayState == .failed && $0.updatedAt > referenceDate.addingTimeInterval(-30 * 60) }.count
        recentlyCompletedCount = allRuns.filter { $0.status == .completed && $0.updatedAt > referenceDate.addingTimeInterval(-30 * 60) }.count
    }

    var activeRunCount: Int {
        runningCount + queuedCount
    }

    var symbolName: String {
        if recentFailureCount > 0 {
            return "exclamationmark.circle.fill"
        }

        if activeRunCount > 0 {
            return "bolt.circle.fill"
        }

        if recentlyCompletedCount > 0 {
            return "checkmark.circle"
        }

        return "bolt.circle"
    }

    var headline: String {
        if recentFailureCount > 0 {
            return "\(recentFailureCount) recent failure\(recentFailureCount == 1 ? "" : "s")"
        }

        if activeRunCount > 0 {
            return "\(activeRunCount) active workflow\(activeRunCount == 1 ? "" : "s")"
        }

        if recentlyCompletedCount > 0 {
            return "Recent activity is clear"
        }

        return "No recent workflow activity"
    }
}

extension Date {
    func relativeDescription(referenceDate: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: referenceDate)
    }

    func elapsedDescription(referenceDate: Date) -> String {
        let interval = max(0, referenceDate.timeIntervalSince(self))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: interval) ?? "0s"
    }
}
