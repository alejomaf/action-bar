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
                    Text("GitHub authentication will use OAuth Device Flow and Keychain-backed tokens.")
                    Text("This first slice is intentionally read-only and running on preview data.")
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
