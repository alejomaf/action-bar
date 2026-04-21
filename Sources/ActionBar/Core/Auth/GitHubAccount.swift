import Foundation

struct GitHubAccount: Codable, Equatable, Sendable {
    let login: String
    let name: String?
    let avatarURL: URL?
    let htmlURL: URL

    var displayName: String {
        name?.isEmpty == false ? name! : login
    }

    var subtitle: String {
        "@\(login)"
    }
}

struct GitHubAuthSession: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let scopes: [String]
}

struct GitHubDeviceAuthorization: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let verificationURLComplete: URL?
    let expiresAt: Date
    let pollingInterval: Duration
}

enum GitHubAuthError: LocalizedError, Equatable, Sendable {
    case missingClientID
    case invalidResponse
    case authorizationDenied
    case expiredDeviceCode
    case missingAccessToken
    case invalidToken
    case unexpectedStatusCode(Int)
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Add a GitHub OAuth Client ID before starting sign-in."
        case .invalidResponse:
            return "GitHub returned an unexpected response."
        case .authorizationDenied:
            return "GitHub sign-in was denied."
        case .expiredDeviceCode:
            return "The GitHub device code expired. Start sign-in again."
        case .missingAccessToken:
            return "GitHub did not return an access token."
        case .invalidToken:
            return "The stored GitHub session is no longer valid."
        case let .unexpectedStatusCode(statusCode):
            return "GitHub returned HTTP \(statusCode)."
        case let .serverError(message):
            return message
        }
    }
}
