import Foundation

// MARK: - Device Flow Response Models

struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }

    init(deviceCode: String, userCode: String, verificationUri: String, expiresIn: Int, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

struct OAuthTokenResponse: Decodable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?
    let interval: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
        case interval
    }
}

// MARK: - OAuth Errors

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

// MARK: - OAuth Service

actor OAuthService {
    static let clientID = "Iv23liMJQvDNiRMhbNes"

    func requestDeviceCode() async throws -> DeviceCodeResponse {
        var request = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": Self.clientID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw OAuthError.codeRequestFailed(code)
        }

        return try JSONDecoder().decode(DeviceCodeResponse.self, from: data)
    }

    func pollForToken(deviceCode: String, interval: Int) async throws -> String {
        var pollInterval = interval

        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: UInt64(pollInterval) * 1_000_000_000)
            try Task.checkCancellation()

            var request = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: String] = [
                "client_id": Self.clientID,
                "device_code": deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await perform(request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw OAuthError.codeRequestFailed(code)
            }

            let tokenResponse = try JSONDecoder().decode(OAuthTokenResponse.self, from: data)

            if let token = tokenResponse.accessToken {
                return token
            }

            switch tokenResponse.error {
            case "authorization_pending":
                continue
            case "slow_down":
                pollInterval = (tokenResponse.interval ?? pollInterval) + 5
                continue
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

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw OAuthError.networkError(error)
        }
    }
}
