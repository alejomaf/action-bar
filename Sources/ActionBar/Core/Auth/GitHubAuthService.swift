import Foundation

actor GitHubAuthService {
    private enum Constants {
        static let sessionAccount = "github-oauth-session"
    }

    private let session: URLSession
    private let keychainStore: KeychainStore
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init(
        session: URLSession = .shared,
        keychainStore: KeychainStore = KeychainStore(service: "com.alejomaf.action-bar.github")
    ) {
        self.session = session
        self.keychainStore = keychainStore

        jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase

        jsonEncoder = JSONEncoder()
    }

    func loadSession() throws -> GitHubAuthSession? {
        guard let data = try keychainStore.read(account: Constants.sessionAccount) else {
            return nil
        }

        return try jsonDecoder.decode(GitHubAuthSession.self, from: data)
    }

    func signOut() throws {
        try keychainStore.delete(account: Constants.sessionAccount)
    }

    func startDeviceAuthorization(clientID: String) async throws -> GitHubDeviceAuthorization {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitHubAuthError.missingClientID
        }

        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody([
            "client_id": clientID,
            "scope": "repo read:user",
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw try decodeServerError(from: data, fallbackStatusCode: httpResponse.statusCode)
        }

        let payload = try jsonDecoder.decode(DeviceAuthorizationResponse.self, from: data)

        return GitHubDeviceAuthorization(
            deviceCode: payload.deviceCode,
            userCode: payload.userCode,
            verificationURL: payload.verificationUri,
            verificationURLComplete: payload.verificationUriComplete,
            expiresAt: .now.addingTimeInterval(TimeInterval(payload.expiresIn)),
            pollingInterval: .seconds(payload.interval)
        )
    }

    func awaitAccessToken(clientID: String, authorization: GitHubDeviceAuthorization) async throws -> GitHubAuthSession {
        var pollingInterval = authorization.pollingInterval

        while Date.now < authorization.expiresAt {
            try await Task.sleep(for: pollingInterval)

            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = formEncodedBody([
                "client_id": clientID,
                "device_code": authorization.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])

            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAuthError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                throw try decodeServerError(from: data, fallbackStatusCode: httpResponse.statusCode)
            }

            let payload = try jsonDecoder.decode(AccessTokenResponse.self, from: data)

            if let accessToken = payload.accessToken,
               let tokenType = payload.tokenType {
                let authSession = GitHubAuthSession(
                    accessToken: accessToken,
                    tokenType: tokenType,
                    scopes: payload.scope
                        .split(separator: ",")
                        .map(String.init)
                        .filter { !$0.isEmpty }
                )

                try persist(authSession)
                return authSession
            }

            switch payload.error {
            case .none:
                throw GitHubAuthError.missingAccessToken
            case .authorizationPending:
                continue
            case .slowDown:
                pollingInterval += .seconds(5)
            case .accessDenied:
                throw GitHubAuthError.authorizationDenied
            case .expiredToken:
                throw GitHubAuthError.expiredDeviceCode
            case let .other(value):
                throw GitHubAuthError.serverError(payload.errorDescription ?? value)
            }
        }

        throw GitHubAuthError.expiredDeviceCode
    }

    func fetchAuthenticatedAccount(accessToken: String) async throws -> GitHubAccount {
        var request = URLRequest(url: URL(string: "https://api.github.com/user")!)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAuthError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            return try jsonDecoder.decode(GitHubAccount.self, from: data)
        case 401:
            try? signOut()
            throw GitHubAuthError.invalidToken
        default:
            throw try decodeServerError(from: data, fallbackStatusCode: httpResponse.statusCode)
        }
    }

    private func persist(_ authSession: GitHubAuthSession) throws {
        let data = try jsonEncoder.encode(authSession)
        try keychainStore.write(data, account: Constants.sessionAccount)
    }

    private func formEncodedBody(_ values: [String: String]) -> Data? {
        values
            .map { key, value in
                "\(key.urlQueryEncoded)=\(value.urlQueryEncoded)"
            }
            .sorted()
            .joined(separator: "&")
            .data(using: .utf8)
    }

    private func decodeServerError(from data: Data, fallbackStatusCode: Int) throws -> GitHubAuthError {
        if let payload = try? jsonDecoder.decode(ServerErrorResponse.self, from: data),
           let message = payload.errorDescription ?? payload.message ?? payload.error {
            return .serverError(message)
        }

        return .unexpectedStatusCode(fallbackStatusCode)
    }
}

private struct DeviceAuthorizationResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: URL
    let verificationUriComplete: URL?
    let expiresIn: Int
    let interval: Int
}

private struct AccessTokenResponse: Decodable {
    let accessToken: String?
    let tokenType: String?
    let scope: String
    let error: DeviceFlowPollingError?
    let errorDescription: String?
}

private struct ServerErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?
    let message: String?
}

private enum DeviceFlowPollingError: Equatable {
    case authorizationPending
    case slowDown
    case accessDenied
    case expiredToken
    case other(String)
}

extension DeviceFlowPollingError: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        switch value {
        case "authorization_pending":
            self = .authorizationPending
        case "slow_down":
            self = .slowDown
        case "access_denied":
            self = .accessDenied
        case "expired_token":
            self = .expiredToken
        default:
            self = .other(value)
        }
    }
}

private extension String {
    var urlQueryEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: ":#[]@!$&'()*+,;="))) ?? self
    }
}
