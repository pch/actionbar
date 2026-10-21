import Foundation

// Responses from the GitHub REST API and OAuth device flow.
// Decoded with `.convertFromSnakeCase`, so property names mirror the JSON keys.

extension JSONDecoder {
    /// A decoder for GitHub REST API responses.
    static func gitHubAPI() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

struct GitHubUser: Decodable {
    let login: String
}

struct Repository: Decodable, Hashable, Identifiable {
    let id: Int
    let fullName: String
}

struct WorkflowRunsResponse: Decodable {
    let workflowRuns: [WorkflowRun]
}

// MARK: - GitHub App Installations

/// A response from a paginated list endpoint that reports the total item count.
protocol PaginatedResponse: Decodable {
    associatedtype Item
    var totalCount: Int { get }
    var items: [Item] { get }
}

struct AppInstallation: Decodable {
    let id: Int
}

struct InstallationsResponse: PaginatedResponse {
    let totalCount: Int
    let installations: [AppInstallation]

    var items: [AppInstallation] { installations }
}

struct InstallationRepositoriesResponse: PaginatedResponse {
    let totalCount: Int
    let repositories: [Repository]

    var items: [Repository] { repositories }
}

// MARK: - OAuth Device Flow

struct DeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationUri: String
    let interval: Int
}

struct OAuthTokenResponse: Decodable {
    let accessToken: String?
    let error: String?
    let errorDescription: String?
    let interval: Int?
}
