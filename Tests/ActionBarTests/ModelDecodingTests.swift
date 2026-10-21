import Foundation
import Testing

struct ModelDecodingTests {
    private let decoder = JSONDecoder.gitHubAPI()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(type, from: Data(json.utf8))
    }

    @Test func workflowRunsResponse() throws {
        let response = try decode(WorkflowRunsResponse.self, """
        {
          "total_count": 1,
          "workflow_runs": [{
            "id": 42,
            "name": "CI",
            "display_title": "Fix login bug",
            "status": "completed",
            "conclusion": "success",
            "event": "push",
            "html_url": "https://github.com/owner/repo/actions/runs/42",
            "head_branch": "main",
            "created_at": "2025-01-02T03:04:05Z",
            "updated_at": "2025-01-02T03:14:05Z",
            "repository": { "full_name": "owner/repo" },
            "actor": { "login": "octocat" },
            "triggering_actor": { "login": "hubot" }
          }]
        }
        """)

        let run = try #require(response.workflowRuns.first)
        #expect(run.id == 42)
        #expect(run.name == "CI")
        #expect(run.title == "Fix login bug")
        #expect(run.status == "completed")
        #expect(run.conclusion == "success")
        #expect(run.event == "push")
        #expect(run.htmlUrl == "https://github.com/owner/repo/actions/runs/42")
        #expect(run.headBranch == "main")
        #expect(run.createdAt == Date(timeIntervalSince1970: 1_735_787_045))
        #expect(run.updatedAt == Date(timeIntervalSince1970: 1_735_787_645))
        #expect(run.repositoryFullName == "owner/repo")
        #expect(run.triggeringActorLogin == "hubot")
    }

    @Test func workflowRunWithOptionalFieldsMissing() throws {
        let run = try decode(WorkflowRun.self, """
        {
          "id": 7,
          "html_url": "https://github.com/owner/repo/actions/runs/7",
          "created_at": "2025-01-02T03:04:05Z",
          "updated_at": "2025-01-02T03:04:05Z",
          "repository": { "full_name": "owner/repo" },
          "actor": { "login": "octocat" }
        }
        """)

        #expect(run.name == nil)
        #expect(run.status == nil)
        #expect(run.headBranch == nil)
        #expect(run.title == "Workflow")
        #expect(run.triggeringActorLogin == "octocat")
    }

    @Test func workflowRunWithoutRepositoryFails() {
        #expect(throws: DecodingError.self) {
            try decode(WorkflowRun.self, """
            {
              "id": 7,
              "html_url": "https://github.com/owner/repo/actions/runs/7",
              "created_at": "2025-01-02T03:04:05Z",
              "updated_at": "2025-01-02T03:04:05Z"
            }
            """)
        }
    }

    @Test func installationRepositoriesResponse() throws {
        let response = try decode(InstallationRepositoriesResponse.self, """
        {
          "total_count": 2,
          "repositories": [
            { "id": 1, "full_name": "owner/first", "private": false },
            { "id": 2, "full_name": "owner/second", "private": true }
          ]
        }
        """)

        #expect(response.totalCount == 2)
        #expect(response.items.map(\.fullName) == ["owner/first", "owner/second"])
    }

    @Test func installationsResponse() throws {
        let response = try decode(InstallationsResponse.self, """
        { "total_count": 1, "installations": [{ "id": 99, "app_id": 1 }] }
        """)

        #expect(response.totalCount == 1)
        #expect(response.items.map(\.id) == [99])
    }

    @Test func deviceCodeResponse() throws {
        let response = try decode(DeviceCodeResponse.self, """
        {
          "device_code": "abc123",
          "user_code": "ABCD-1234",
          "verification_uri": "https://github.com/login/device",
          "expires_in": 900,
          "interval": 5
        }
        """)

        #expect(response.deviceCode == "abc123")
        #expect(response.userCode == "ABCD-1234")
        #expect(response.verificationUri == "https://github.com/login/device")
        #expect(response.interval == 5)
    }

    @Test func oauthTokenResponses() throws {
        let success = try decode(OAuthTokenResponse.self, """
        { "access_token": "token", "token_type": "bearer", "scope": "" }
        """)
        #expect(success.accessToken == "token")
        #expect(success.error == nil)

        let pending = try decode(OAuthTokenResponse.self, """
        { "error": "slow_down", "error_description": "Too many requests.", "interval": 10 }
        """)
        #expect(pending.accessToken == nil)
        #expect(pending.error == "slow_down")
        #expect(pending.errorDescription == "Too many requests.")
        #expect(pending.interval == 10)
    }
}
