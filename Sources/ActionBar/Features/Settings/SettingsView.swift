import AppKit
import SwiftUI

struct SettingsView: View {
    let store: AppStore
    @State private var repositoryInput = ""
    @State private var repositoryInputError: String?
    @State private var showAdvanced = false

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

            if store.repositories.isEmpty {
                Text("No tracked repositories yet.")
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
                Button("Restore defaults") {
                    store.restorePreviewRepositories()
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
