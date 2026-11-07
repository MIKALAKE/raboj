import Foundation
import Testing
@testable import RabojCore

@Suite struct PaceTests {
    let reset = Date(timeIntervalSince1970: 1_800_000_000)

    private func window(used: Double, length: TimeInterval = 5 * 3_600) -> PlanWindow {
        PlanWindow(id: "s", title: "Current session", usedPercent: used, resetsAt: reset, length: length)
    }

    @Test func onTrackProjectsTheEndOfTheWindow() {
        // Halfway through the window at 30% → ~60% by reset.
        let pace = window(used: 30).pace(now: reset.addingTimeInterval(-2.5 * 3_600))
        guard case .onTrack(let projected) = pace else { Issue.record("expected on track, got \(String(describing: pace))"); return }
        #expect(abs(projected - 60) < 0.01)
    }

    @Test func fastUsageHitsTheLimitBeforeReset() {
        // 1 hour in, 76% used → 100% at about 1h 19m.
        let now = reset.addingTimeInterval(-4 * 3_600)
        guard case .willHitLimit(let at) = window(used: 76).pace(now: now) else { Issue.record("expected limit"); return }
        #expect(abs(at.timeIntervalSince(now) - 3_600 * 24.0 / 76.0) < 1)
    }

    @Test func edgeCases() {
        #expect(window(used: 100).pace(now: reset) == .limitReached)
        // Too early in the window to judge a non-zero rate.
        #expect(window(used: 20).pace(now: reset.addingTimeInterval(-5 * 3_600 + 60)) == nil)
        // No length known: no estimate.
        #expect(PlanWindow(id: "x", title: "x", usedPercent: 40, resetsAt: reset).pace(now: reset.addingTimeInterval(-60)) == nil)
    }
}

@Suite struct StatusLineSetupTests {
    @Test func detectsState() {
        #expect(ClaudeStatusLineSetup.state(of: nil) == .missingFile)
        #expect(ClaudeStatusLineSetup.state(of: Data(#"{"model":"opus"}"#.utf8)) == .notSetUp)
        #expect(ClaudeStatusLineSetup.state(of: Data(#"{"statusLine":{"type":"command","command":"my-line.sh"}}"#.utf8)) == .otherStatusLine("my-line.sh"))
        let merged = ClaudeStatusLineSetup.mergedSettings(nil)!
        #expect(ClaudeStatusLineSetup.state(of: Data(merged.utf8)) == .setUp)
    }

    @Test func mergeKeepsOtherSettings() throws {
        let existing = Data(#"{"model":"opus","permissions":{"allow":["Bash(ls)"]},"statusLine":{"type":"command","command":"old"}}"#.utf8)
        let merged = try #require(ClaudeStatusLineSetup.mergedSettings(existing))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(merged.utf8)) as? [String: Any])
        #expect(object["model"] as? String == "opus")
        #expect((object["permissions"] as? [String: [String]])?["allow"] == ["Bash(ls)"])
        #expect((object["statusLine"] as? [String: String])?["command"] == ClaudeStatusLineSetup.command)
        #expect(!merged.contains("\\/"))
    }

    @Test func invalidJSONIsNotOverwritten() {
        #expect(ClaudeStatusLineSetup.mergedSettings(Data("{ not json".utf8)) == nil)
    }
}
