import AppKit
import SwiftUI

struct SettingsView: View {
    let store: AppStore
    @State private var repositoryInput = ""
    @State private var repositoryInputError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    LabeledContent("Refresh cadence") {
                        Text(store.summary.activeRunCount > 0 ? "15s while active" : "60s while idle")
                    }

                    LabeledContent("Status") {
                        Text(store.dataMode == .preview ? "Preview mode" : "Live sync")
                    }
                }

                Section("Repositories") {
                    HStack(spacing: 8) {
                        TextField("owner/name", text: $repositoryInput)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addRepository)

                        Button("Add", action: addRepository)
                            .keyboardShortcut(.defaultAction)
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
                            HStack {
                                Text(repository.fullName)
                                Spacer(minLength: 0)
                                Button("Remove") {
                                    store.removeRepository(repository)
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }

                    Button("Restore defaults") {
                        store.restorePreviewRepositories()
                        repositoryInputError = nil
                    }
                }

                Section("Account") {
                    TextField(
                        "GitHub OAuth Client ID",
                        text: Binding(
                            get: { store.gitHubOAuthClientID },
                            set: { store.updateGitHubOAuthClientID($0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Text("Register a GitHub OAuth App and paste its Client ID here. No client secret is required for Device Flow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let account = store.authenticatedAccount {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(account.displayName)
                                .font(.headline)
                            Text(account.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Link("Open GitHub Profile", destination: account.htmlURL)
                        }

                        Button("Sign Out") {
                            store.signOutFromGitHub()
                        }
                    } else if let authorization = store.activeDeviceAuthorization {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Enter this code on GitHub")
                                .font(.subheadline.weight(.semibold))

                            Text(authorization.userCode)
                                .font(.system(.title3, design: .monospaced).weight(.semibold))

                            Link(
                                "Open GitHub Verification Page",
                                destination: authorization.verificationURLComplete ?? authorization.verificationURL
                            )

                            HStack(spacing: 10) {
                                Button("Copy Code") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(authorization.userCode, forType: .string)
                                }

                                Button("Cancel") {
                                    store.cancelGitHubDeviceFlow()
                                }
                            }
                        }
                    } else {
                        Button(store.isAuthenticating ? "Waiting for GitHub..." : "Sign In with GitHub") {
                            store.startGitHubDeviceFlow()
                        }
                        .disabled(!store.hasOAuthClientID || store.isAuthenticating)
                    }

                    if let authStatusMessage = store.authStatusMessage {
                        Text(authStatusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let authErrorMessage = store.authErrorMessage {
                        Text(authErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Text("When signed out, Action Bar falls back to preview data. Once signed in, workflow activity loads live from GitHub.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
        .frame(minWidth: 520, minHeight: 400)
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
