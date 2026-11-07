import CoreGraphics
import Foundation
import Testing
@testable import RabojCore

private func data(_ string: String) -> Data { Data(string.utf8) }
private let day = Timestamps.parse("2026-11-07T00:00:00Z")!

@Suite struct GeminiParserTests {
    let message = #"{"id":"m1","timestamp":"2026-11-07T10:00:00.000Z","type":"gemini","content":[{"text":"hi"}],"model":"gemini-3-pro","tokens":{"input":1200,"output":80,"cached":1000,"thoughts":40,"tool":10,"total":1330}}"#

    @Test func parsesTokens() throws {
        let event = try #require(GeminiLogParser.parse(line: data(message), project: "my-app"))
        #expect(event.key == "ge|m1")
        #expect(event.model == "gemini-3-pro")
        // input includes cached; thoughts are output; tool-use prompt tokens are input.
        #expect(event.tokens == TokenCounts(input: 210, output: 120, cacheWrite: 0, cacheRead: 1000))
        #expect(event.project == "my-app")
    }

    @Test func skipsUserMessagesAndMessagesWithoutTokens() {
        let user = #"{"id":"u1","timestamp":"2026-11-07T10:00:00.000Z","type":"user","content":[{"text":"gemini tokens?"}]}"#
        let noTokens = #"{"id":"m2","timestamp":"2026-11-07T10:00:00.000Z","type":"gemini","content":[],"model":"gemini-3-pro"}"#
        #expect(GeminiLogParser.parse(line: data(user)) == nil)
        #expect(GeminiLogParser.parse(line: data(noTokens)) == nil)
    }

    @Test func reAppendedMessagesCountOnce() {
        var ledger = UsageLedger()
        ledger.merge([message, message].compactMap { GeminiLogParser.parse(line: data($0)) })
        #expect(ledger.events.count == 1)
    }

    @Test func projectComesFromTheTmpSubfolder() {
        #expect(GeminiLogParser.project(for: URL(fileURLWithPath: "/Users/x/.gemini/tmp/my-app/chats/session-1.jsonl")) == "my-app")
    }
}

@Suite struct MoreAPITests {
    @Test func xAIDailyCostByModel() throws {
        let json = #"{"timeSeries":[{"group":["Chat grok-4-0709"],"groupLabels":["Chat grok-4-0709"],"dataPoints":[{"timestamp":"2025-10-01T00:00:00Z","values":[0.75]},{"timestamp":"2025-10-02T00:00:00Z","values":[0]}]}],"limitReached":false}"#
        let events = try XAIManagementAPI.decodeUsage(data(json))
        #expect(events.count == 1)
        #expect(events[0].model == "grok-4-0709")
        #expect(events[0].costUSD == 0.75)
    }

    @Test func xAIRequestBodyMatchesTheDocs() throws {
        let body = try JSONSerialization.jsonObject(with: XAIManagementAPI.body(from: day, to: day.addingTimeInterval(86_400))) as? [String: Any]
        let request = try #require(body?["analyticsRequest"] as? [String: Any])
        #expect(request["timeUnit"] as? String == "TIME_UNIT_DAY")
        #expect((request["timeRange"] as? [String: String])?["startTime"] == "2026-11-07 00:00:00")
    }

    @Test func copilotRequestsAndCostPerModel() throws {
        let json = #"{"timePeriod":{"year":2026,"month":11,"day":7},"user":"me","usageItems":[{"product":"Copilot","sku":"Copilot Premium Request","model":"Claude Sonnet","unitType":"requests","pricePerUnit":0.04,"grossQuantity":12,"grossAmount":0.48,"discountQuantity":12,"discountAmount":0.48,"netQuantity":0,"netAmount":0},{"product":"Copilot","sku":"Copilot Premium Request","model":"Claude Sonnet","unitType":"requests","pricePerUnit":0.04,"grossQuantity":3,"grossAmount":0.12,"discountQuantity":0,"discountAmount":0,"netQuantity":3,"netAmount":0.12}]}"#
        let events = try CopilotBillingAPI.decodeDay(data(json), day: day)
        #expect(events.count == 1)
        #expect(events[0].requests == 15)
        #expect(abs((events[0].costUSD ?? 0) - 0.12) < 0.0001)
    }

    @Test func cursorDailyRequestsAndSpend() throws {
        let daily = #"{"data":[{"userId":1,"day":"2026-11-07","date":1794009600000,"email":"a@x","composerRequests":3,"chatRequests":2,"agentRequests":5,"cmdkUsages":1,"mostUsedModel":"claude-sonnet"},{"userId":2,"date":1794009600000,"composerRequests":0,"chatRequests":0,"agentRequests":0}],"period":{"startDate":0,"endDate":0}}"#
        let events = try CursorAdminAPI.decodeDaily(data(daily))
        #expect(events.count == 1)
        #expect(events[0].requests == 11)
        let spend = #"{"teamMemberSpend":[{"spendCents":1250},{"spendCents":"250"}],"subscriptionCycleStart":1793000000000,"totalMembers":2,"totalPages":1}"#
        let decoded = try CursorAdminAPI.decodeSpend(data(spend))
        #expect(decoded.cents == 1500)
        #expect(decoded.totalPages == 1)
    }

    @Test func openRouterKeyUsageAndLimit() throws {
        let json = #"{"data":{"label":"k","limit":20,"limit_remaining":15,"limit_reset":"monthly","usage":42.5,"usage_daily":1.25,"usage_weekly":6,"usage_monthly":5,"is_free_tier":false}}"#
        let fetch = try OpenRouterKeyAPI.decode(data(json), now: day.addingTimeInterval(3_600))
        #expect(fetch.events.first?.costUSD == 1.25)
        #expect(fetch.events.first?.timestamp == day)
        #expect(fetch.plan?.windows.first?.usedPercent == 25)
        #expect(fetch.info.map(\.title) == ["This week (UTC)", "This month (UTC)", "All time on this key"])
    }

    @Test func deepSeekBalance() throws {
        let json = #"{"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"110.00","granted_balance":"10.00","topped_up_balance":"100.00"}]}"#
        let items = try DeepSeekBalanceAPI.decode(data(json))
        #expect(items.first?.value == "¥110.00")
        #expect(items.first?.detail == "topped up ¥100.00 · granted ¥10.00")
    }

    @Test func everyAPIProviderHasHostsAndAClient() {
        for provider in Provider.allCases where provider.connection == .apiKey {
            #expect(!provider.allowedHosts.isEmpty, "\(provider)")
            #expect(provider.api != nil, "\(provider)")
            #expect(!provider.keyHelp.isEmpty, "\(provider)")
        }
    }

    @Test func requestsDriveTheSummaryWhenThereAreNoTokens() {
        var ledger = UsageLedger()
        ledger.merge([UsageEvent(key: "a", timestamp: day.addingTimeInterval(3_600), model: "Claude Sonnet", tokens: .zero, requests: 15)])
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let summary = ledger.summary(.today, now: day.addingTimeInterval(7_200), calendar: utc)
        #expect(summary.requests == 15)
        #expect(summary.byModel.first?.name == "Claude Sonnet")
    }
}

@Suite struct SVGPathTests {
    @Test func drawsCommandsIncludingArcsAndCompactNumbers() {
        // Absolute/relative lines, curves, a compact arc ("a1 1 0 011 1") and a close.
        let path = SVGPath.cgPath("M2 2h10v10H2zM4.5.5l1-1c1 1 2 2 3 3s1 1 2 2q1 1 2 2t1 1a1 1 0 011 1A2 2 0 0 0 20 20z")
        let box = path.boundingBoxOfPath
        #expect(box.minX <= 2 && box.maxX >= 20)
        #expect(box.maxY >= 20)
    }

    @Test func everyBundledLogoParses() {
        for provider in Provider.allCases {
            guard let logo = provider.logo else { continue }
            let box = SVGPath.cgPath(logo.path).boundingBoxOfPath
            #expect(box.width > 10 && box.width <= 24.5, "\(provider)")
            #expect(box.height > 5 && box.height <= 24.5, "\(provider)")
        }
    }
}
