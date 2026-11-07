import Foundation
import Testing
@testable import RabojCore

private func line(_ string: String) -> Data { Data(string.utf8) }

@Suite struct ClaudeCodeLogParserTests {
    let assistant = #"{"type":"assistant","timestamp":"2026-11-07T20:20:53.490Z","requestId":"req_1","cwd":"/Users/x/code/my-app","message":{"id":"msg_1","model":"claude-opus-5-5","content":[{"type":"text","text":"hello"}],"usage":{"input_tokens":2,"cache_creation_input_tokens":30572,"cache_read_input_tokens":30931,"output_tokens":541}}}"#

    @Test func parsesAssistantUsage() throws {
        let event = try #require(ClaudeCodeLogParser.parse(line: line(assistant)))
        #expect(event.key == "cc|msg_1|req_1")
        #expect(event.model == "claude-opus-5-5")
        #expect(event.project == "my-app")
        #expect(event.tokens == TokenCounts(input: 2, output: 541, cacheWrite: 30572, cacheRead: 30931))
        #expect(abs(event.timestamp.timeIntervalSince1970 - 1_794_082_853.49) < 0.001)
    }

    @Test func repeatedLinesForOneResponseCountOnce() {
        var ledger = UsageLedger()
        // Claude Code writes one line per content block, all with the same id and usage.
        let events = [assistant, assistant, assistant].compactMap { ClaudeCodeLogParser.parse(line: line($0)) }
        ledger.merge(events)
        #expect(events.count == 3)
        #expect(ledger.events.count == 1)
    }

    @Test func ignoresUserLinesSyntheticAndBrokenLines() {
        let user = #"{"type":"user","timestamp":"2026-11-07T20:20:53Z","message":{"role":"user","content":"what is usage?"}}"#
        let synthetic = assistant.replacingOccurrences(of: "claude-opus-5-5", with: "<synthetic>")
        #expect(ClaudeCodeLogParser.parse(line: line(user)) == nil)
        #expect(ClaudeCodeLogParser.parse(line: line(synthetic)) == nil)
        #expect(ClaudeCodeLogParser.parse(line: line("{not json \"usage\" \"type\":\"assistant\"")) == nil)
    }

    @Test func parsesStatusLineLimits() throws {
        let json = #"{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}"#
        let plan = try #require(ClaudeCodeLogParser.parseLimits(line(json), capturedAt: Date(timeIntervalSince1970: 1_738_400_000)))
        #expect(plan.windows.map(\.title) == ["5-hour limit", "Weekly limit"])
        #expect(plan.windows[0].usedPercent == 23.5)
        #expect(plan.windows[0].resetsAt == Date(timeIntervalSince1970: 1_738_425_600))
        #expect(plan.activeWindows(now: Date(timeIntervalSince1970: 1_738_500_000)).map(\.id) == ["seven_day"])
    }

    @Test func statusLineSnippetIsValidJSON() throws {
        let object = try JSONSerialization.jsonObject(with: Data("{\(ClaudeStatusLineSetup.settingsSnippet)}".utf8)) as? [String: Any]
        let statusLine = try #require(object?["statusLine"] as? [String: String])
        #expect(statusLine["command"] == ClaudeStatusLineSetup.command)
    }
}

@Suite struct CodexParserTests {
    let turnContext = #"{"timestamp":"2026-10-28T14:21:15.000Z","type":"turn_context","payload":{"model":"gpt-x-codex","cwd":"/Users/x/code/api-service"}}"#
    let record1 = #"{"timestamp":"2026-10-28T14:21:20.000Z","type":"token_usage_record","payload":{"response_id":"resp_1","usage":{"input_tokens":13381,"cached_input_tokens":6016,"cache_write_input_tokens":0,"output_tokens":166,"reasoning_output_tokens":96,"total_tokens":13547}}}"#
    let tokenCount = #"{"timestamp":"2026-10-28T14:21:21.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":13381,"cached_input_tokens":6016,"cache_write_input_tokens":0,"output_tokens":166,"total_tokens":13547}},"rate_limits":{"primary":{"used_percent":3.0,"window_minutes":43200,"resets_at":1795708020},"secondary":{"used_percent":31.0,"window_minutes":10080,"resets_at":1795000000},"plan_type":"go"}}}"#

    @Test func usageRecordsAreKeyedByResponse() {
        let parser = CodexSessionParser(fileID: "a.jsonl", usesUsageRecords: true)
        _ = parser.consume(line: line(turnContext))
        let output = parser.consume(line: line(record1))
        #expect(output.events.count == 1)
        let event = output.events[0]
        #expect(event.key == "cx|resp_1")
        #expect(event.model == "gpt-x-codex")
        #expect(event.project == "api-service")
        // input_tokens includes the cached part.
        #expect(event.tokens == TokenCounts(input: 7365, output: 166, cacheWrite: 0, cacheRead: 6016))
        // With usage records present, token_count totals are not counted again.
        #expect(parser.consume(line: line(tokenCount)).events.isEmpty)
    }

    @Test func olderFilesUseTotalDeltas() {
        let parser = CodexSessionParser(fileID: "b.jsonl", usesUsageRecords: false)
        let first = parser.consume(line: line(tokenCount))
        let again = parser.consume(line: line(tokenCount))
        #expect(first.events.first?.tokens.total == 13547)
        #expect(again.events.isEmpty)
    }

    @Test func readsPlanLimits() throws {
        let parser = CodexSessionParser(fileID: "c.jsonl", usesUsageRecords: true)
        let plan = try #require(parser.consume(line: line(tokenCount)).plan)
        #expect(plan.windows.map(\.title) == ["30-day limit", "Weekly limit"])
        #expect(plan.windows[1].usedPercent == 31)
        #expect(plan.windows[0].resetsAt == Date(timeIntervalSince1970: 1_795_708_020))
    }

    @Test func detectsUsageRecords() {
        #expect(CodexSessionParser.fileUsesUsageRecords(line(record1)))
        #expect(!CodexSessionParser.fileUsesUsageRecords(line(tokenCount)))
    }
}

@Suite struct TailerTests {
    @Test func readsOnlyNewCompleteLines() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("p"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("p/s.jsonl")
        try Data("one\ntwo\npart".utf8).write(to: file)

        let tailer = JSONLTailer()
        var lines: [String] = []
        var firstReads: [Bool] = []
        let collect: (URL, Bool, Data) -> Void = { _, first, chunk in
            firstReads.append(first)
            chunk.forEachCompleteLine { lines.append(String(decoding: $0, as: UTF8.self)) }
        }
        tailer.readNew(under: dir, cutoff: .distantPast, chunk: collect)
        #expect(lines == ["one", "two"])

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("ial\nthree\n".utf8))
        try handle.close()
        tailer.readNew(under: dir, cutoff: .distantPast, chunk: collect)
        #expect(lines == ["one", "two", "partial", "three"])
        #expect(firstReads == [true, false])

        // Nothing new: no callback.
        tailer.readNew(under: dir, cutoff: .distantPast, chunk: collect)
        #expect(firstReads.count == 2)

        // A rewritten, shorter file is read again from the start.
        try Data("new\n".utf8).write(to: file)
        tailer.readNew(under: dir, cutoff: .distantPast, chunk: collect)
        #expect(lines.last == "new")
    }

    @Test func skipsOldFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("old.jsonl")
        try Data("x\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -100 * 86_400)], ofItemAtPath: file.path)
        var called = false
        JSONLTailer().readNew(under: dir, cutoff: Date(timeIntervalSinceNow: -62 * 86_400)) { _, _, _ in called = true }
        #expect(!called)
    }
}
