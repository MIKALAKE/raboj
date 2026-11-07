import Foundation

/// Reads `.jsonl` files under a folder incrementally: each call returns only bytes appended since the last call.
///
/// - Files not modified since `cutoff` are skipped unless already being followed.
/// - A partial last line is left for the next call.
/// - A file that shrank (rewritten or rotated) is read again from the start.
public final class JSONLTailer {
    private struct FileState {
        var offset: UInt64
    }

    private var states: [String: FileState] = [:]
    private let fileManager = FileManager.default

    public init() {}

    /// - Parameters:
    ///   - root: folder to scan recursively.
    ///   - cutoff: ignore files last modified before this date.
    ///   - chunk: called with the file URL, whether this is the first read of that file, and the new bytes
    ///            (complete lines only). Return nothing; the tailer advances past every complete line.
    public func readNew(under root: URL, cutoff: Date, chunk: (URL, Bool, Data) -> Void) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return }
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let path = url.path
            let size = UInt64(values.fileSize ?? 0)
            let known = states[path]
            if known == nil, let modified = values.contentModificationDate, modified < cutoff { continue }

            var offset = known?.offset ?? 0
            if size < offset { offset = 0 }
            guard size > offset else { continue }
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: offset)
                guard let data = try handle.readToEnd(), !data.isEmpty else { continue }
                var complete = Data()
                let consumed = data.forEachCompleteLine { _ in }
                if consumed > 0 { complete = data.prefix(consumed) }
                if !complete.isEmpty { chunk(url, known == nil || offset == 0, complete) }
                states[path] = FileState(offset: offset + UInt64(consumed))
            } catch {
                continue
            }
        }
    }

    /// Forget every file, so the next read starts from scratch.
    public func reset() { states.removeAll() }
}
