import AppKit
import Foundation
import RabojCore
import Security

/// Folder picking and security-scoped bookmarks.
enum FolderAccess {
    /// The user's real home folder. Inside the sandbox `NSHomeDirectory()` points at the app container.
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Shows the standard macOS folder picker, starting at the provider's usual folder.
    @MainActor
    static func choose(for provider: Provider) -> (url: URL, bookmark: Data?)? {
        chooseFolders(for: provider, multiple: false).first
    }

    /// Like `choose`, but lets the user ⌘-click several folders (one account per folder).
    @MainActor
    static func chooseMany(for provider: Provider) -> [(url: URL, bookmark: Data?)] {
        chooseFolders(for: provider, multiple: true)
    }

    @MainActor
    private static func chooseFolders(for provider: Provider, multiple: Bool) -> [(url: URL, bookmark: Data?)] {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = multiple
        panel.showsHiddenFiles = true
        panel.prompt = "Allow read access"
        panel.message = multiple
            ? "Choose the \(provider.displayName) data folders, one per account (⌘-click to pick several). Răboj only reads usage from them."
            : "Choose the \(provider.displayName) data folder. Răboj only reads usage from it."
        // Open the home folder so ~/.claude and ~/.claude-* sit side by side.
        panel.directoryURL = realHome
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.map { url in
            (url, try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil))
        }
    }

    static func resolve(_ bookmark: Data) -> (url: URL, stale: Bool)? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        return (url, stale)
    }

    /// Shortens /Users/name/... to ~/... for display.
    static func displayPath(_ path: String) -> String {
        let home = realHome.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

/// API keys live in the macOS Keychain, one item per account.
enum Keychain {
    private static let service = "io.github.mikalake.raboj.api-key"

    private static func query(_ account: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account.uuidString]
    }

    @discardableResult
    static func save(_ key: String, for account: UUID) -> Bool {
        SecItemDelete(query(account) as CFDictionary)
        var item = query(account)
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrLabel as String] = "Răboj API key"
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func read(_ account: UUID) -> String? {
        var item = query(account)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: UUID) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

extension AccountColor {
    var nsColor: NSColor {
        let pair: (UInt32, UInt32) = switch self {
        case .blue: (0x2563EB, 0x60A5FA)
        case .orange: (0xD97706, 0xF59E0B)
        case .teal: (0x0F766E, 0x2DD4BF)
        case .purple: (0x7C3AED, 0xA78BFA)
        case .graphite: (0x52525B, 0xA1A1AA)
        case .pink: (0xBE185D, 0xF472B6)
        case .green: (0x15803D, 0x4ADE80)
        case .red: (0xDC2626, 0xF87171)
        case .amber: (0xCA8A04, 0xFACC15)
        case .indigo: (0x4338CA, 0x818CF8)
        case .cyan: (0x0891B2, 0x22D3EE)
        case .brown: (0x92400E, 0xC2884A)
        }
        return NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: dark ? pair.1 : pair.0)
        }
    }

    var title: String { rawValue.capitalized }
}

extension Account {
    /// The account's color: the custom one if picked, else the preset.
    var nsColor: NSColor { customColorHex.map { NSColor(hex: $0) } ?? color.nsColor }
}

extension NSColor {
    /// 0xRRGGBB in sRGB.
    var hexValue: UInt32 {
        let c = usingColorSpace(.sRGB) ?? self
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }

    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The tally-stick glyph: four strokes crossed by a fifth.
enum TallyIcon {
    static func image(size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size * 0.875), flipped: false) { rect in
            let s = rect.width / 16
            let path = NSBezierPath()
            path.lineWidth = 1.6 * s
            path.lineCapStyle = .round
            for x in [3.0, 6.5, 10.0, 13.5] {
                path.move(to: NSPoint(x: x * s, y: 2.2 * s))
                path.line(to: NSPoint(x: x * s, y: 11.8 * s))
            }
            path.move(to: NSPoint(x: 1.3 * s, y: 3.6 * s))
            path.line(to: NSPoint(x: 15.2 * s, y: 10.4 * s))
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
