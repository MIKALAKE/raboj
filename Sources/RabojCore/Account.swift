import Foundation

/// An AI tool whose usage Răboj can read.
public enum Provider: String, Codable, CaseIterable, Sendable {
    case claudeCode
    case codex

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// The data folder the tool uses when no override is configured.
    /// Shown as a suggestion in the folder picker; Răboj never reads it without the user choosing it.
    public var defaultFolderName: String {
        switch self {
        case .claudeCode: ".claude"
        case .codex: ".codex"
        }
    }
}

/// One account = one provider + one data folder the user granted access to.
/// The model allows any number of accounts per provider.
public struct Account: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var provider: Provider
    /// User-chosen label, e.g. "Work". Never derived from emails or login data.
    public var label: String
    public var color: AccountColor

    public init(id: UUID = UUID(), provider: Provider, label: String, color: AccountColor) {
        self.id = id
        self.provider = provider
        self.label = label
        self.color = color
    }
}

/// Account colors, chosen so neighbours also differ in lightness (readable for color-blind users).
public enum AccountColor: String, Codable, CaseIterable, Sendable {
    case blue, orange, teal, purple, graphite

    /// The next color not used yet by `existing`, cycling when all are taken.
    public static func next(after existing: [AccountColor]) -> AccountColor {
        allCases.first { !existing.contains($0) } ?? allCases[existing.count % allCases.count]
    }
}
