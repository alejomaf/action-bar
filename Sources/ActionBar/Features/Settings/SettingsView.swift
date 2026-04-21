import AppKit
import SwiftUI

struct SettingsView: View {
    let store: AppStore
    @State private var repositoryInput = ""
    @State private var repositoryInputError: String?
    @State private var showAdvanced = false
    @State private var showRepositoryPicker = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                repositoriesSection
                generalSection
                advancedSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
        .frame(minWidth: 540, minHeight: 460)
        .sheet(isPresented: $showRepositoryPicker) {
            RepositoryPickerView(store: store)
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        Section("Account") {
            if let account = store.authenticatedAccount {
                HStack(spacing: 12) {
                    AccountAvatar(url: account.avatarURL, size: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName)
                            .font(.headline)
                        Text(account.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Link(destination: account.htmlURL) {
                        Label("Profile", systemImage: "arrow.up.right.square")
                    }
                }

                Button(role: .destructive) {
                    store.signOutFromGitHub()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } else if let authorization = store.activeDeviceAuthorization {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter this code on GitHub")
                        .font(.subheadline.weight(.semibold))

                    Text(authorization.userCode)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))

                    HStack(spacing: 10) {
                        Link(
                            "Open verification page",
                            destination: authorization.verificationURLComplete ?? authorization.verificationURL
                        )

                        Button("Copy code") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(authorization.userCode, forType: .string)
                        }

                        Button("Check now") {
                            store.retryGitHubDevicePolling()
                        }
                        .disabled(store.isAuthenticating)

                        Button("Cancel") {
                            store.cancelGitHubDeviceFlow()
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in with GitHub to load live workflow runs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        store.startGitHubDeviceFlow()
                    } label: {
                        Label(
                            store.isAuthenticating ? "Waiting for GitHub..." : "Sign in with GitHub",
                            systemImage: "person.badge.key"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!store.hasOAuthClientID || store.isAuthenticating)
                }
            }

            if let authStatusMessage = store.authStatusMessage {
                Text(authStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let authErrorMessage = store.authErrorMessage {
                Label(authErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Repositories

    private var repositoriesSection: some View {
        Section {
            HStack(spacing: 8) {
                TextField("owner/name", text: $repositoryInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addRepository)

                Button("Add", action: addRepository)
                    .keyboardShortcut(.defaultAction)
                    .disabled(repositoryInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let repositoryInputError {
                Text(repositoryInputError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button {
                    showRepositoryPicker = true
                } label: {
                    Label("Browse my GitHub repos", systemImage: "magnifyingglass")
                }
                .disabled(!store.isSignedInToGitHub)
                .help(store.isSignedInToGitHub ? "Pick from repositories you can access" : "Sign in to browse your repositories")

                Spacer(minLength: 0)

                if !store.isSignedInToGitHub {
                    Text("Sign in to browse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if store.repositories.isEmpty {
                Text("No tracked repositories yet. Add one above or browse your GitHub repos.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.repositories) { repository in
                    HStack(spacing: 8) {
                        Image(systemName: "book.closed")
                            .foregroundStyle(.secondary)
                        Text(repository.fullName)
                        Spacer(minLength: 0)
                        Link(destination: URL(string: "https://github.com/\(repository.fullName)")!) {
                            Image(systemName: "arrow.up.right.square")
                        }
                        .help("Open on GitHub")
                        Button {
                            store.removeRepository(repository)
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                }
            }

            HStack {
                Button("Add example repos") {
                    store.restoreExampleRepositories()
                    repositoryInputError = nil
                }
                Spacer(minLength: 0)
                Text("\(store.repositories.count) tracked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Repositories")
        } footer: {
            Text("Use `owner/name`, e.g. `apple/swift`. Repositories are stored locally.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section("General") {
            LabeledContent("Refresh cadence") {
                Text(store.summary.activeRunCount > 0 ? "15s while active" : "60s while idle")
            }

            LabeledContent("Data source") {
                HStack(spacing: 6) {
                    Image(systemName: store.dataMode == .preview ? "sparkles" : "dot.radiowaves.left.and.right")
                        .foregroundStyle(store.dataMode == .preview ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.green))
                    Text(store.dataMode == .preview ? "Preview" : "Live")
                }
            }

            if let rateLimit = store.rateLimit {
                LabeledContent("GitHub API") {
                    Text("\(rateLimit.remaining) of \(rateLimit.limit) calls remaining")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OAuth Client ID override")
                        .font(.subheadline.weight(.semibold))
                    TextField(
                        "Bundled by default",
                        text: Binding(
                            get: { store.gitHubOAuthClientID },
                            set: { store.updateGitHubOAuthClientID($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Text("Action Bar ships with a default OAuth Client ID. Override only for development or self-hosted forks. No client secret is required (Device Flow).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func addRepository() {
        do {
            try store.addRepository(from: repositoryInput)
            repositoryInput = ""
            repositoryInputError = nil
        } catch {
            repositoryInputError = error.localizedDescription
        }
    }
}

private struct AccountAvatar: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.quaternary, lineWidth: 0.5))
    }

    private var placeholder: some View {
        Image("logo", bundle: .module)
            .resizable()
            .scaledToFill()
    }
}

// MARK: - Repository picker

struct RepositoryPickerView: View {
    let store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var allRepositories: [GitHubRepositorySummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var search = ""

    private var trackedIDs: Set<String> {
        Set(store.repositories.map(\.id))
    }

    private var filteredRepositories: [GitHubRepositorySummary] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return allRepositories }
        return allRepositories.filter {
            $0.fullName.lowercased().contains(trimmed) ||
            ($0.description ?? "").lowercased().contains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading && allRepositories.isEmpty {
                    ProgressView("Loading your repositories...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .font(.callout)
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filteredRepositories) { repo in
                        RepositoryPickerRow(
                            repo: repo,
                            isTracked: trackedIDs.contains(repo.id),
                            onAdd: { store.addRepository(repo.repository) }
                        )
                    }
                    .listStyle(.inset)
                    .searchable(text: $search, placement: .toolbar, prompt: "Filter repositories")
                }
            }
            .navigationTitle("Add a repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                    .help("Reload")
                }
            }
        }
        .frame(minWidth: 520, minHeight: 460)
        .task {
            if allRepositories.isEmpty {
                await load()
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let repos = try await store.fetchUserRepositories()
            allRepositories = repos.sorted { lhs, rhs in
                (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RepositoryPickerRow: View {
    let repo: GitHubRepositorySummary
    let isTracked: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: repo.isPrivate ? "lock" : (repo.isFork ? "tuningfork" : "book.closed"))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(repo.fullName)
                    .font(.subheadline.weight(.medium))
                if let description = repo.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isTracked {
                Label("Added", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .help("Already tracking")
            } else {
                Button {
                    onAdd()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help("Add")
            }
        }
        .padding(.vertical, 2)
    }
}
