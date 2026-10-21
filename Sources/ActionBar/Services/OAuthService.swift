import Foundation

/// The GitHub App ActionBar signs in through. Forks must register their own app and update these values.
enum GitHubApp {
    static let clientID = "Iv23liMJQvDNiRMhbNes"
    static let installationURL = URL(string: "https://github.com/apps/actionbar-macos")!
}

enum OAuthError: Error, LocalizedError {
    case codeRequestFailed(Int)
    case expired
    case denied
    case networkError(Error)
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .codeRequestFailed(let code):
            return "Failed to start login (HTTP \(code))"
        case .expired:
            return "Login timed out. Please try again."
        case .denied:
            return "Access was denied. Please try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .unexpected(let msg):
            return msg
        }
    }
}

/// Signs in with the OAuth device flow:
/// https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
struct OAuthService {
    private static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    private static let accessTokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func requestDeviceCode() async throws -> DeviceCodeResponse {
        let data = try await post(Self.deviceCodeURL, body: ["client_id": GitHubApp.clientID])
        return try decoder.decode(DeviceCodeResponse.self, from: data)
    }

    func pollForToken(deviceCode: String, interval: Int) async throws -> String {
        var pollInterval = interval

        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(pollInterval))
            try Task.checkCancellation()

            let data = try await post(Self.accessTokenURL, body: [
                "client_id": GitHubApp.clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            let tokenResponse = try decoder.decode(OAuthTokenResponse.self, from: data)

            if let token = tokenResponse.accessToken {
                return token
            }

            switch tokenResponse.error {
            case "authorization_pending":
                continue
            case "slow_down":
                pollInterval = (tokenResponse.interval ?? pollInterval) + 5
            case "expired_token":
                throw OAuthError.expired
            case "access_denied":
                throw OAuthError.denied
            default:
                throw OAuthError.unexpected(
                    tokenResponse.errorDescription ?? "Unknown error: \(tokenResponse.error ?? "nil")"
                )
            }
        }
    }

    private func post(_ url: URL, body: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OAuthError.networkError(error)
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            throw OAuthError.codeRequestFailed(statusCode)
        }
        return data
    }
}
