import Foundation

enum RepositoryInputError: LocalizedError {
    case invalidFullName

    var errorDescription: String? {
        switch self {
        case .invalidFullName:
            return "Enter a repository as owner/name."
        }
    }
}

struct Repository: Codable, Hashable, Identifiable, Sendable {
    let owner: String
    let name: String

    var id: String {
        normalizedFullName
    }

    var normalizedFullName: String {
        "\(owner.lowercased())/\(name.lowercased())"
    }

    var fullName: String {
        "\(owner)/\(name)"
    }

    init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    init(validating fullName: String) throws {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: false)

        guard components.count == 2,
              !components[0].isEmpty,
              !components[1].isEmpty else {
            throw RepositoryInputError.invalidFullName
        }

        self.init(owner: String(components[0]), name: String(components[1]))
    }
}

extension Repository {
    static let previewDefaults: [Repository] = [
        Repository(owner: "apple", name: "swift"),
        Repository(owner: "swiftlang", name: "swift-package-manager"),
        Repository(owner: "pointfreeco", name: "swift-composable-architecture"),
    ]
}
