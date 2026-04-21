import AppKit
import SwiftUI

struct MenuBarPanel: View {
    private enum WindowID {
        static let settings = "settings"
    }

    @Environment(\.openWindow) private var openWindow
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if store.runGroups.isEmpty {
                ContentUnavailableView(
                    "No workflow activity yet",
                    systemImage: "bolt.slash",
                    description: Text("Add repositories and sign in to GitHub to see runs here.")
                )
                .padding()
                .frame(minHeight: 170)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if store.dataMode == .preview {
                            PreviewBanner()
                        }

                        ForEach(store.runGroups) { group in
                            RepositorySection(group: group)
                        }
                    }
                    .padding(16)
                }
                .frame(minHeight: 220, maxHeight: 420)
            }

            Divider()
            footer
        }
        .frame(width: 380)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Action Bar")
                    .font(.headline)
                Text(store.summary.headline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            HeaderActionButton(systemName: "arrow.clockwise", helpText: "Refresh") {
                Task {
                    await store.refresh()
                }
            }

            HeaderActionButton(systemName: "gearshape", helpText: "Settings") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.settings)
            }
        }
        .padding(16)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }

            HStack(spacing: 8) {
                Text(lastRefreshText)
                Spacer(minLength: 0)
                if let rateLimit = store.rateLimit {
                    Text("Rate \(rateLimit.remaining)/\(rateLimit.limit)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var lastRefreshText: String {
        guard let lastRefresh = store.lastRefresh else {
            return "Not refreshed yet"
        }

        return "Updated \(lastRefresh.relativeDescription(referenceDate: .now))"
    }
}

private struct HeaderActionButton: View {
    let systemName: String
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary.opacity(0.35))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }
}

struct StatusBarLabel: View {
    let summary: ActivitySummary
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: summary.symbolName)
            if summary.activeRunCount > 0 {
                Text(summary.activeRunCount, format: .number)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }
}

private struct PreviewBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview fallback")
                    .font(.subheadline.weight(.semibold))
                Text("Sign in with GitHub to switch this panel from sample activity to live workflow runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }
}

private struct RepositorySection: View {
    let group: RepositoryRunGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.repository.fullName)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if let activeRun = group.runs.first(where: \.isActive) {
                    Text(activeRun.relativeTimestamp())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 8) {
                ForEach(group.runs) { run in
                    WorkflowRunRow(run: run)
                }
            }
        }
    }
}

private struct WorkflowRunRow: View {
    let run: WorkflowRun

    var body: some View {
        Button {
            NSWorkspace.shared.open(run.htmlURL)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: run.displayState.symbolName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 4) {
                    Text(run.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)

                    Text("\(run.branch) · \(run.actor) · \(run.relativeTimestamp())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if run.isRecentFailure {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in GitHub") {
                NSWorkspace.shared.open(run.htmlURL)
            }

            if let logsURL = run.logsURL {
                Button("Open Logs") {
                    NSWorkspace.shared.open(logsURL)
                }
            }

            Button("Copy Run URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(run.htmlURL.absoluteString, forType: .string)
            }
        }
    }

    private var iconColor: Color {
        switch run.displayState {
        case .queued:
            return .orange
        case .running:
            return .accentColor
        case .succeeded:
            return .green
        case .failed:
            return .red
        case .cancelled, .neutral:
            return .secondary
        }
    }
}
