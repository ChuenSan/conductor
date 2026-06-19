import XCTest
@testable import ConductorCore

final class LiteLLMUsageTests: XCTestCase {
    func testManagementEndpointsStripV1Suffix() throws {
        let baseURL = try XCTUnwrap(URL(string: "https://litellm.example.com/proxy/v1"))

        XCTAssertEqual(
            LiteLLMUsageFetcher.keyInfoURL(baseURL: baseURL).absoluteString,
            "https://litellm.example.com/proxy/key/info")
        XCTAssertEqual(
            LiteLLMUsageFetcher.userInfoURL(baseURL: baseURL, userID: "user-1").absoluteString,
            "https://litellm.example.com/proxy/user/info?user_id=user-1")
        XCTAssertEqual(
            LiteLLMUsageFetcher.teamInfoURL(baseURL: baseURL, teamID: "team-1").absoluteString,
            "https://litellm.example.com/proxy/team/info?team_id=team-1")
    }

    func testParseUserBudgetAndPreferredTeam() throws {
        let keyData = """
        {
          "info": {
            "key_name": "Dev Key",
            "spend": 12.5,
            "expires": "2026-07-01T00:00:00Z",
            "user_id": "user-1",
            "team_id": "team-1"
          }
        }
        """.data(using: .utf8)!
        let userData = """
        {
          "user_id": "user-1",
          "user_info": {
            "user_id": "user-1",
            "user_email": "dev@example.com",
            "max_budget": 100,
            "spend": 25,
            "budget_reset_at": "2026-07-01T00:00:00Z",
            "metadata": { "preferred_username": "dev" }
          },
          "teams": [
            {
              "team_alias": "Core",
              "team_id": "team-1",
              "max_budget": 500,
              "spend": 125,
              "budget_reset_at": "2026-07-01T00:00:00Z",
              "budget_duration": "30d"
            }
          ]
        }
        """.data(using: .utf8)!
        let updatedAt = ISO8601DateFormatter().date(from: "2026-06-18T00:00:00Z")!

        let keyInfo = try LiteLLMUsageFetcher.parseKeyInfo(keyData)
        let usage = try LiteLLMUsageFetcher.parseUserInfo(userData, keyInfo: keyInfo, updatedAt: updatedAt)
        let snapshot = usage.toUsageSnapshot()

        XCTAssertEqual(snapshot.planName, "Dev Key")
        XCTAssertEqual(snapshot.accountLabel, "dev@example.com · Core")
        XCTAssertEqual(snapshot.primary?.title, L("个人预算"))
        XCTAssertEqual(snapshot.primary?.usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.secondary?.title, L("团队预算"))
        XCTAssertEqual(snapshot.secondary?.usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.providerCost?.used, 25)
        XCTAssertEqual(snapshot.providerCost?.limit, 100)
        XCTAssertEqual(snapshot.providerCost?.period, L("个人预算"))
    }

    func testParseTeamOnlyBudget() throws {
        let keyData = """
        {
          "info": {
            "key_name": "Team Key",
            "spend": 30,
            "team_id": "team-2"
          }
        }
        """.data(using: .utf8)!
        let teamData = """
        {
          "team_id": "team-2",
          "team_info": {
            "team_alias": "Growth",
            "team_id": "team-2",
            "max_budget": 200,
            "spend": 50,
            "budget_reset_at": "2026-07-01T00:00:00Z",
            "budget_duration": "30d"
          }
        }
        """.data(using: .utf8)!

        let keyInfo = try LiteLLMUsageFetcher.parseKeyInfo(keyData)
        let usage = try LiteLLMUsageFetcher.parseTeamInfo(teamData, keyInfo: keyInfo, updatedAt: Date())
        let snapshot = usage.toUsageSnapshot()

        XCTAssertNil(snapshot.primary)
        XCTAssertEqual(snapshot.secondary?.title, L("团队预算"))
        XCTAssertEqual(snapshot.secondary?.usedPercent ?? -1, 25, accuracy: 0.001)
        XCTAssertEqual(snapshot.accountLabel, "Growth")
        XCTAssertEqual(snapshot.providerCost?.used, 50)
        XCTAssertEqual(snapshot.providerCost?.limit, 200)
        XCTAssertEqual(snapshot.providerCost?.period, L("团队预算"))
    }
}
