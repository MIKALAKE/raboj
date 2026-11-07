import Foundation

/// Reads usage from Gemini CLI's chat recordings (`~/.gemini/tmp/<project>/chats/*.jsonl`).
///
/// Source of the format: `packages/core/src/services/chatRecordingService.ts` in google-gemini/gemini-cli.
/// A `gemini` message carries `model` and `tokens` (`input` = promptTokenCount, which includes `cached`;
/// `output`, `thoughts`, `tool`, `total`). The recorder re-appends a message whenever it updates it,
/// so the same `id` can appear several times; the last line wins.
public enum GeminiLogParser {
    private static let geminiMarker = Data(#""gemini""#.utf8)
    private static let tokensMarker = Data(#""tokens""#.utf8)

    private struct Record: Decodable {
        let id: String?
        let timestamp: String?
        let type: String?
        let model: String?
        let tokens: Tokens?
    }

    private struct Tokens: Decodable {
        let input: Int?
        let output: Int?
        let cached: Int?
        let thoughts: Int?
        let tool: Int?
    }

    public static func parse(line: Data, project: String? = nil) -> UsageEvent? {
        guard line.range(of: tokensMarker) != nil, line.range(of: geminiMarker) != nil,
              let record = try? JSONDecoder().decode(Record.self, from: line),
              record.type == "gemini",
              let id = record.id,
              let tokens = record.tokens,
              let timestampString = record.timestamp,
              let timestamp = Timestamps.parse(timestampString)
        else { return nil }
        let cached = tokens.cached ?? 0
        let counts = TokenCounts(
            input: max(0, (tokens.input ?? 0) - cached) + (tokens.tool ?? 0),
            output: (tokens.output ?? 0) + (tokens.thoughts ?? 0),
            cacheWrite: 0,
            cacheRead: cached
        )
        guard counts.total > 0 else { return nil }
        return UsageEvent(key: "ge|\(id)", timestamp: timestamp, model: record.model ?? "gemini", tokens: counts, project: project)
    }

    /// `<root>/tmp/<project>/chats/...` → `<project>`.
    public static func project(for file: URL) -> String? {
        let parts = file.pathComponents
        guard let tmp = parts.lastIndex(of: "tmp"), tmp + 1 < parts.count else { return nil }
        return parts[tmp + 1]
    }
}
