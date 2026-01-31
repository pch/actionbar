import Foundation

enum GitHubAPIError: Error, LocalizedError {
    case invalidToken
    case networkError(Error)
    case invalidResponse(Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidToken:
            return "Invalid or expired token"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let code):
            return "GitHub API returned status \(code)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        }
    }
}

actor GitHubAPIClient {
    private let baseURL = "https://api.github.com"
    private let session: URLSession
    private let decoder: JSONDecoder

    init() {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        ]
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Token Validation

    func validateToken(_ token: String) async throws -> GitHubUser {
        let request = makeRequest(path: "/user", token: token)
        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse(0)
        }

        if httpResponse.statusCode == 401 {
            throw GitHubAPIError.invalidToken
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubAPIError.invalidResponse(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(GitHubUser.self, from: data)
        } catch {
            throw GitHubAPIError.decodingError(error)
        }
    }

    // MARK: - Fetch Workflow Runs

    func fetchRecentRuns(token: String, actor: String? = nil, repos repoNames: [String]? = nil) async throws -> [WorkflowRun] {
        let repoFullNames: [String]
        if let repoNames {
            repoFullNames = repoNames
        } else {
            repoFullNames = try await fetchRepos(token: token).map(\.fullName)
        }

        return await withTaskGroup(of: [WorkflowRun].self) { group in
            for repoName in repoFullNames {
                group.addTask {
                    do {
                        return try await self.fetchRunsForRepo(repo: repoName, token: token, actor: actor)
                    } catch {
                        // Silently skip repos where we can't fetch runs (e.g. no Actions configured)
                        return []
                    }
                }
            }

            var allRuns: [WorkflowRun] = []
            for await runs in group {
                allRuns.append(contentsOf: runs)
            }

            // Filter out automated/scheduled runs (cron jobs, dependabot, etc.)
            let excludedEvents: Set<String> = ["schedule", "repository_dispatch"]
            allRuns = allRuns.filter { run in
                guard let event = run.event else { return true }
                return !excludedEvents.contains(event)
            }

            allRuns.sort { $0.updatedAt > $1.updatedAt }
            return Array(allRuns.prefix(20))
        }
    }

    func fetchAllRepos(token: String) async throws -> [Repository] {
        var allRepos: [Repository] = []
        var page = 1
        let maxRepos = 200

        while allRepos.count < maxRepos {
            let request = makeRequest(
                path: "/user/repos",
                queryItems: [
                    URLQueryItem(name: "sort", value: "full_name"),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: "\(page)"),
                ],
                token: token
            )

            let (data, response) = try await perform(request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitHubAPIError.invalidResponse(0)
            }

            if httpResponse.statusCode == 401 {
                throw GitHubAPIError.invalidToken
            }

            guard httpResponse.statusCode == 200 else {
                throw GitHubAPIError.invalidResponse(httpResponse.statusCode)
            }

            let repos: [Repository]
            do {
                repos = try decoder.decode([Repository].self, from: data)
            } catch {
                throw GitHubAPIError.decodingError(error)
            }

            if repos.isEmpty { break }
            allRepos.append(contentsOf: repos)
            if repos.count < 100 { break }
            page += 1
        }

        return Array(allRepos.prefix(maxRepos))
    }

    // MARK: - Private

    private func fetchRepos(token: String) async throws -> [Repository] {
        let request = makeRequest(
            path: "/user/repos",
            queryItems: [
                URLQueryItem(name: "sort", value: "pushed"),
                URLQueryItem(name: "per_page", value: "10"),
            ],
            token: token
        )

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse(0)
        }

        if httpResponse.statusCode == 401 {
            throw GitHubAPIError.invalidToken
        }

        guard httpResponse.statusCode == 200 else {
            throw GitHubAPIError.invalidResponse(httpResponse.statusCode)
        }

        do {
            return try decoder.decode([Repository].self, from: data)
        } catch {
            throw GitHubAPIError.decodingError(error)
        }
    }

    private func fetchRunsForRepo(repo: String, token: String, actor: String? = nil) async throws -> [WorkflowRun] {
        var queryItems = [URLQueryItem(name: "per_page", value: "5")]
        if let actor {
            queryItems.append(URLQueryItem(name: "actor", value: actor))
        }

        let request = makeRequest(
            path: "/repos/\(repo)/actions/runs",
            queryItems: queryItems,
            token: token
        )

        let (data, response) = try await perform(request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        do {
            let runsResponse = try decoder.decode(WorkflowRunsResponse.self, from: data)
            return runsResponse.workflowRuns
        } catch {
            return []
        }
    }

    private func makeRequest(path: String, queryItems: [URLQueryItem] = [], token: String) -> URLRequest {
        var components = URLComponents(string: baseURL + path)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw GitHubAPIError.networkError(error)
        }
    }
}
