import Foundation
import Testing

struct FetchFailureTests {
    private let serverError = GitHubAPIError.invalidResponse(500)

    @Test func noErrorsReturnsResults() {
        #expect(GitHubAPIError.failingWholeFetch([], requestedRepoCount: 2) == nil)
    }

    @Test func someReposFailingReturnsPartialResults() {
        // One repo failed; the other loaded, even if it had no runs.
        #expect(GitHubAPIError.failingWholeFetch([serverError], requestedRepoCount: 2) == nil)
    }

    @Test func everyRepoFailingFailsTheFetch() throws {
        let error = try #require(GitHubAPIError.failingWholeFetch([serverError, serverError], requestedRepoCount: 2))
        guard case GitHubAPIError.invalidResponse(500) = error else {
            Issue.record("Expected the first repo's error, got \(error)")
            return
        }
    }

    @Test func invalidTokenOnAnyRepoFailsTheFetch() throws {
        let error = try #require(GitHubAPIError.failingWholeFetch(
            [serverError, GitHubAPIError.invalidToken],
            requestedRepoCount: 5
        ))
        guard case GitHubAPIError.invalidToken = error else {
            Issue.record("Expected invalidToken, got \(error)")
            return
        }
    }

    @Test func rateLimitOnAnyRepoFailsTheFetch() throws {
        let error = try #require(GitHubAPIError.failingWholeFetch([GitHubAPIError.rateLimited], requestedRepoCount: 5))
        guard case GitHubAPIError.rateLimited = error else {
            Issue.record("Expected rateLimited, got \(error)")
            return
        }
    }
}
