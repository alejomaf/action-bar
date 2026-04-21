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
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .onAppear {
            store.resumeGitHubDevicePollingIfNeeded()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            AccountBadge(account: store.authenticatedAccount)

            VStack(alignment: .leading, spacing: 2) {
                Text(headerTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(store.summary.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HeaderActionButton(
                systemName: "arrow.clockwise",
                helpText: "Refresh now",
                isSpinning: store.isRefreshing
            ) {
                Task { await store.refresh() }
            }

            HeaderActionButton(systemName: "gearshape", helpText: "Open Settings") {
                openSettings()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerTitle: String {
        if let account = store.authenticatedAccount {
            return account.displayName
        }
        return "Action Bar"
    }

    // MARK: - Content

    private static let maxRunsPerRepo = 3

    private var activeRuns: [ActiveRunEntry] {
        store.runGroups.flatMap { group in
            group.runs
                .filter(\.isActive)
                .map { ActiveRunEntry(run: $0, repository: group.repository) }
        }
        .sorted { $0.run.sortDate > $1.run.sortDate }
    }

    private var trimmedGroups: [RepositoryRunGroup] {
        store.runGroups.compactMap { group in
            let recent = group.runs.prefix(Self.maxRunsPerRepo)
            guard !recent.isEmpty else { return nil }
            return RepositoryRunGroup(repository: group.repository, runs: Array(recent))
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.activeDeviceAuthorization != nil || store.isAuthenticating {
            DeviceFlowCard(store: store)
                .padding(16)
        } else if !store.isSignedInToGitHub {
            SignInCard(store: store, openSettings: openSettings)
                .padding(16)
        } else if store.runGroups.isEmpty {
            EmptyRepositoriesView(openSettings: openSettings)
                .frame(minHeight: 180)
        } else {
            // Re-render every second so live timestamps stay fresh while the panel is open.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if store.dataMode == .preview {
                            PreviewBanner()
                        }

                        let active = activeRuns
                        if !active.isEmpty {
                            ActiveRunsSection(entries: active, referenceDate: context.date)
                        }

                        ForEach(trimmedGroups) { group in
                            RepositorySection(group: group, referenceDate: context.date)
                        }
                    }
                    .padding(16)
                }
                .frame(minHeight: 220, maxHeight: 420)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .lineLimit(2)
            }

            HStack(spacing: 6) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(lastRefreshText(referenceDate: context.date))
                }
                if let rateLimit = store.rateLimit {
                    Text("·")
                    Text("API \(rateLimit.remaining)/\(rateLimit.limit)")
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                FooterLink(title: "Settings", systemName: "gearshape") {
                    openSettings()
                }

                FooterLink(title: "GitHub", systemName: "arrow.up.right.square") {
                    if let url = URL(string: "https://github.com") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Spacer(minLength: 0)

                FooterLink(title: "Quit", systemName: "power") {
                    NSApp.terminate(nil)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func lastRefreshText(referenceDate: Date = .now) -> String {
        guard let lastRefresh = store.lastRefresh else {
            return "Not refreshed yet"
        }
        return "Updated \(lastRefresh.relativeDescription(referenceDate: referenceDate))"
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.settings)
    }
}

// MARK: - Header pieces

private struct AccountBadge: View {
    let account: GitHubAccount?

    var body: some View {
        RemoteAvatar(url: account?.avatarURL)
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            .overlay(
                Circle().strokeBorder(.quaternary, lineWidth: 0.5)
            )
    }
}

private struct HeaderActionButton: View {
    let systemName: String
    let helpText: String
    var isSpinning: Bool = false
    let action: () -> Void

    @State private var rotation: Double = 0

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(rotation))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.quaternary.opacity(0.35))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText)
        .onChange(of: isSpinning) { _, newValue in
            if newValue {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    rotation += 360
                }
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    rotation = 0
                }
            }
        }
    }
}

private struct FooterLink: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                Text(title)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

// MARK: - Status bar label

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

// MARK: - Sign-in / Device flow cards

private struct SignInCard: View {
    let store: AppStore
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect to GitHub")
                        .font(.subheadline.weight(.semibold))
                    Text("Sign in to see live workflow runs from your repos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                store.startGitHubDeviceFlow()
            } label: {
                HStack {
                    Image(systemName: "person.badge.key")
                    Text("Sign in with GitHub")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(!store.hasOAuthClientID || store.isAuthenticating)

            if let authErrorMessage = store.authErrorMessage {
                Label(authErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Showing preview data meanwhile")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Advanced", action: openSettings)
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DeviceFlowCard: View {
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.horizontal")
                    .foregroundStyle(.tint)
                Text("Authorize Action Bar on GitHub")
                    .font(.subheadline.weight(.semibold))
            }

            if let authorization = store.activeDeviceAuthorization {
                Text(authorization.userCode)
                    .font(.system(.title, design: .monospaced).weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.quaternary.opacity(0.4))
                    )

                HStack(spacing: 8) {
                    Button {
                        let url = authorization.verificationURLComplete ?? authorization.verificationURL
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open GitHub", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(authorization.userCode, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }

                if store.isAuthenticating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(store.authStatusMessage ?? "Waiting for GitHub...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else {
                    Text("Action Bar will detect the authorization automatically. If you already authorized, tap \"Check now\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let authErrorMessage = store.authErrorMessage {
                    Label(authErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }

                HStack(spacing: 12) {
                    Button {
                        store.retryGitHubDevicePolling()
                    } label: {
                        Label("Check now", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isAuthenticating)

                    Spacer(minLength: 0)

                    Button("Cancel") {
                        store.cancelGitHubDeviceFlow()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            } else if let status = store.authStatusMessage {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Cancel") {
                    store.cancelGitHubDeviceFlow()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
    }
}

private struct EmptyRepositoriesView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("No repositories yet")
                    .font(.subheadline.weight(.semibold))
                Text("Add the repos you care about to follow their GitHub Actions here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                openSettings()
            } label: {
                Label("Add Repository", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}

private struct PreviewBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview data")
                    .font(.caption.weight(.semibold))
                Text("Showing sample runs while live data loads.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.5))
        )
    }
}

// MARK: - Repository sections

struct ActiveRunEntry: Identifiable, Hashable {
    let run: WorkflowRun
    let repository: Repository
    var id: String { "\(repository.id)#\(run.id)" }
}

private struct ActiveRunsSection: View {
    let entries: [ActiveRunEntry]
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.tint)
                Text("Active runs")
                    .font(.subheadline.weight(.semibold))
                Text("\(entries.count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(.tint.opacity(0.18))
                    )
                    .foregroundStyle(.tint)
                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(entries) { entry in
                    WorkflowRunRow(
                        run: entry.run,
                        referenceDate: referenceDate,
                        repositoryLabel: entry.repository.fullName
                    )
                }
            }
        }
    }
}

private struct RepositorySection: View {
    let group: RepositoryRunGroup
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.repository.fullName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                Button {
                    if let url = URL(string: "https://github.com/\(group.repository.fullName)/actions") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Actions on GitHub")
            }

            VStack(spacing: 8) {
                ForEach(group.runs) { run in
                    WorkflowRunRow(run: run, referenceDate: referenceDate)
                }
            }
        }
    }
}

private struct WorkflowRunRow: View {
    let run: WorkflowRun
    let referenceDate: Date
    var repositoryLabel: String? = nil

    @State private var pulse: Bool = false

    private var subtitle: String {
        var parts: [String] = []
        if let repositoryLabel {
            parts.append(repositoryLabel)
        }
        parts.append(run.branch)
        parts.append(run.actor)
        parts.append(run.relativeTimestamp(referenceDate: referenceDate))
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(run.htmlURL)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    Image(systemName: run.displayState.symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconColor)
                    if run.isActive {
                        Circle()
                            .stroke(iconColor.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                            .scaleEffect(pulse ? 1.25 : 1.0)
                            .opacity(pulse ? 0.0 : 0.8)
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 4) {
                    Text(run.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
        .onAppear {
            if run.isActive {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    pulse = true
                }
            }
        }
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
