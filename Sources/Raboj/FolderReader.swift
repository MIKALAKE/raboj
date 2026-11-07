import Foundation
import RabojCore

/// What one poll of a folder account found.
struct ReadResult {
    var events: [UsageEvent] = []
    var plan: PlanSnapshot?
    /// Non-time-series values from an API (balances, limits); nil means "unchanged".
    var info: [InfoItem]?
    var error: String?
}

/// Reads one folder account (Claude Code or Codex) incrementally on its own background queue.
final class FolderReader {
    /// How far back usage is kept: 30-day views plus the 30 days they are compared with.
    static let retention: TimeInterval = 62 * 86_400

    let provider: Provider
    let root: URL
    private let accessing: Bool
    private let queue: DispatchQueue
    private let tailer = JSONLTailer()
    private var codexParsers: [String: CodexSessionParser] = [:]
    private var limitsModified: Date?

    init(provider: Provider, root: URL, accessing: Bool) {
        self.provider = provider
        self.root = root
        self.accessing = accessing
        queue = DispatchQueue(label: "raboj.reader.\(root.lastPathComponent)", qos: .utility)
    }

    deinit {
        if accessing { root.stopAccessingSecurityScopedResource() }
    }

    /// Claude Code keeps logs in `projects/`, Codex in `sessions/`, Gemini CLI in `tmp/`;
    /// accept the tool's data folder or that subfolder itself.
    static func logsFolder(for provider: Provider, root: URL) -> URL {
        guard let name = provider.logsSubfolder else { return root }
        let sub = root.appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: sub.path, isDirectory: &isDirectory), isDirectory.boolValue { return sub }
        return root
    }

    /// True when the folder looks like the provider's data folder.
    static func looksValid(_ url: URL, for provider: Provider) -> Bool {
        guard let name = provider.logsSubfolder else { return true }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent(name).path) || url.lastPathComponent == name
    }

    func poll(_ completion: @escaping (ReadResult) -> Void) {
        queue.async { [self] in
            completion(readNow())
        }
    }

    /// Synchronous read, used by the background queue and by `--report`.
    func readNow() -> ReadResult {
        var result = ReadResult()
        let logs = Self.logsFolder(for: provider, root: root)
        guard FileManager.default.isReadableFile(atPath: logs.path) else {
            result.error = "Can’t read \(root.path). Choose the folder again in Settings."
            return result
        }
        let cutoff = Date().addingTimeInterval(-Self.retention)
        tailer.readNew(under: logs, cutoff: cutoff) { url, firstRead, chunk in
            switch provider {
            case .claudeCode:
                let fallback = url.deletingLastPathComponent().lastPathComponent
                chunk.forEachCompleteLine { line in
                    if let event = ClaudeCodeLogParser.parse(line: line, fallbackProject: fallback) { result.events.append(event) }
                }
            case .codex:
                if firstRead || codexParsers[url.path] == nil {
                    codexParsers[url.path] = CodexSessionParser(fileID: url.path, usesUsageRecords: CodexSessionParser.fileUsesUsageRecords(chunk))
                }
                guard let parser = codexParsers[url.path] else { return }
                chunk.forEachCompleteLine { line in
                    let output = parser.consume(line: line)
                    result.events += output.events
                    if let plan = output.plan, plan.capturedAt > (result.plan?.capturedAt ?? .distantPast) { result.plan = plan }
                }
            case .geminiCLI:
                let project = GeminiLogParser.project(for: url)
                chunk.forEachCompleteLine { line in
                    if let event = GeminiLogParser.parse(line: line, project: project) { result.events.append(event) }
                }
            default:
                break
            }
        }
        if provider == .claudeCode { readClaudeLimits(into: &result) }
        return result
    }

    private func readClaudeLimits(into result: inout ReadResult) {
        let file = root.appendingPathComponent(ClaudeCodeLogParser.limitsFileName)
        guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
              modified != limitsModified,
              let data = try? Data(contentsOf: file) else { return }
        limitsModified = modified
        result.plan = ClaudeCodeLogParser.parseLimits(data, capturedAt: modified)
    }
}
