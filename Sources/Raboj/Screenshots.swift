import AppKit
import RabojCore
import SwiftUI

/// `Raboj --screenshots <folder>` renders the README images from made-up demo data.
/// Nothing is read from disk, the Keychain or the network, so no real usage ends up in the images.
@MainActor
enum Screenshots {
    static func render(to folder: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let demo = Demo.make()

        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            let all = popover(demo, selection: .all, metric: .auto, appearance: appearance)
            let claude = popover(demo, selection: .account(demo.personal.id), metric: .auto, appearance: appearance)
            let hero = compose([all, claude], appearance: appearance)
            write(hero, to: folder.appendingPathComponent("hero-\(name).png"))

        }
        // Settings in light mode only: off-screen, the dark toolbar picker doesn't draw correctly.
        let settings = snapshot(
            SettingsView(initialTab: .accounts, initialAccount: demo.personal.id).environmentObject(demo.model()),
            size: NSSize(width: 760, height: 540), appearance: .aqua, windowChrome: true)
        write(compose([crop(settings, height: 470)], appearance: .aqua), to: folder.appendingPathComponent("settings.png"))
        print("Wrote screenshots to \(folder.path)")
    }

    private static func popover(_ demo: Demo, selection: Selection, metric: AllMetric, appearance: NSAppearance.Name) -> NSImage {
        let model = demo.model()
        model.selection = selection
        model.allMetric = metric
        return snapshot(PopoverView().environmentObject(model), size: nil, appearance: appearance, windowChrome: false)
    }

    /// Renders a view at 2× through a real (off-screen) window so AppKit-backed controls draw too.
    private static func snapshot<V: View>(_ view: V, size: NSSize?, appearance: NSAppearance.Name, windowChrome: Bool) -> NSImage {
        let host = NSHostingView(rootView: view.background(Color(nsColor: windowChrome ? .windowBackgroundColor : .controlBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        let fitting = size ?? host.fittingSize
        host.frame = NSRect(origin: .zero, size: fitting)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = host
        window.layoutIfNeeded()
        // Let SwiftUI finish layout and async updates.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()

        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(fitting.width * scale), pixelsHigh: Int(fitting.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = fitting
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: fitting)
        image.addRepresentation(rep)
        return image
    }

    /// Places the panels side by side on a soft gradient with rounded corners and shadows.
    private static func compose(_ panels: [NSImage], appearance: NSAppearance.Name) -> NSImage {
        let dark = appearance == .darkAqua
        let margin: CGFloat = 48, gap: CGFloat = 36
        let height = panels.map(\.size.height).max() ?? 0
        let width = panels.map(\.size.width).reduce(0, +) + gap * CGFloat(panels.count - 1)
        let size = NSSize(width: width + margin * 2, height: height + margin * 2)

        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let background = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 28, yRadius: 28)
        let gradient = dark
            ? NSGradient(starting: NSColor(hex: 0x1E293B), ending: NSColor(hex: 0x0F172A))!
            : NSGradient(starting: NSColor(hex: 0xDBEAFE), ending: NSColor(hex: 0xFDE7D3))!
        gradient.draw(in: background, angle: -35)

        var x = margin
        for panel in panels {
            let rect = NSRect(x: x, y: margin + (height - panel.size.height), width: panel.size.width, height: panel.size.height)
            let clip = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.55 : 0.22)
            shadow.shadowBlurRadius = 28
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.set()
            NSColor.windowBackgroundColor.setFill()
            clip.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            panel.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            NSColor(white: dark ? 1 : 0, alpha: 0.12).setStroke()
            clip.lineWidth = 1
            clip.stroke()
            x += panel.size.width + gap
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    /// Keeps the top `height` points of an image.
    private static func crop(_ image: NSImage, height: CGFloat) -> NSImage {
        let size = NSSize(width: image.size.width, height: height)
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(at: .zero, from: NSRect(x: 0, y: image.size.height - height, width: size.width, height: height), operation: .copy, fraction: 1)
        result.unlockFocus()
        return result
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let rep = image.representations.first as? NSBitmapImageRep,
              let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}

/// Made-up accounts and usage for the screenshots.
@MainActor
private struct Demo {
    let personal = Account(provider: .claudeCode, label: "Personal", color: .blue, folderPath: "~/.claude-personal", pinnedInMenuBar: true)
    let work = Account(provider: .claudeCode, label: "Work", color: .orange, folderPath: "~/.claude", pinnedInMenuBar: true)
    let codex = Account(provider: .codex, label: "Codex", color: .teal, folderPath: "~/.codex")
    let openRouter = Account(provider: .openRouter, label: "Bots", color: .purple)
    let now: Date
    let ledgers: [UUID: UsageLedger]

    static func make() -> Demo {
        // A fixed afternoon so the images don't change between runs.
        let calendar = Calendar.current
        let now = calendar.date(bySettingHour: 16, minute: 20, second: 0, of: Date())!
        return Demo(now: now)
    }

    init(now: Date) {
        self.now = now
        var generator = SeededGenerator(seed: 7)
        func events(prefix: String, models: [(String, Double)], projects: [String], dailyTokens: Double, cost: Double? = nil) -> [UsageEvent] {
            var result: [UsageEvent] = []
            for day in 0..<30 {
                let weekday = Calendar.current.component(.weekday, from: now.addingTimeInterval(Double(-day) * 86_400))
                let weekend = weekday == 1 || weekday == 7
                let dayScale = (weekend ? 0.35 : 1.0) * Double.random(in: 0.6...1.4, using: &generator)
                let messages = day == 0 ? 14 : 20
                for index in 0..<messages {
                    let hoursAgo = day == 0 ? Double(index) * 0.45 + 0.1 : Double(day) * 24 + Double(index) * 0.5
                    let pick = Double.random(in: 0..<1, using: &generator)
                    var cumulative = 0.0
                    let model = models.first { cumulative += $0.1; return pick < cumulative }?.0 ?? models[0].0
                    let tokens = dailyTokens * dayScale / Double(messages)
                    result.append(UsageEvent(
                        key: "\(prefix)\(day)-\(index)",
                        timestamp: now.addingTimeInterval(-hoursAgo * 3_600),
                        model: model,
                        tokens: TokenCounts(input: Int(tokens * 0.02), output: Int(tokens * 0.03), cacheWrite: Int(tokens * 0.08), cacheRead: Int(tokens * 0.87)),
                        costUSD: cost.map { $0 * dayScale / Double(messages) },
                        project: projects[Int.random(in: 0..<projects.count, using: &generator)]
                    ))
                }
            }
            return result
        }

        var personalLedger = UsageLedger()
        personalLedger.merge(events(prefix: "p", models: [("claude-opus-5-5", 0.7), ("claude-sonnet-5-5", 0.25), ("claude-haiku-5-5", 0.05)],
                                    projects: ["raboj", "website", "dotfiles"], dailyTokens: 38_000_000))
        personalLedger.offer(plan: PlanSnapshot(windows: [
            PlanWindow(id: "five_hour", title: "Current session", usedPercent: 46, resetsAt: now.addingTimeInterval(2 * 3_600 + 40 * 60), length: 5 * 3_600),
            PlanWindow(id: "seven_day", title: "This week", usedPercent: 31, resetsAt: now.addingTimeInterval(3 * 86_400 + 5 * 3_600), length: 7 * 86_400),
        ], capturedAt: now.addingTimeInterval(-120), source: "from Claude Code's status line"))

        var workLedger = UsageLedger()
        workLedger.merge(events(prefix: "w", models: [("claude-sonnet-5-5", 0.6), ("claude-opus-5-5", 0.4)],
                                projects: ["api", "mobile-app", "infra"], dailyTokens: 61_000_000))
        workLedger.offer(plan: PlanSnapshot(windows: [
            PlanWindow(id: "five_hour", title: "Current session", usedPercent: 83, resetsAt: now.addingTimeInterval(55 * 60), length: 5 * 3_600),
            PlanWindow(id: "seven_day", title: "This week", usedPercent: 52, resetsAt: now.addingTimeInterval(4 * 86_400), length: 7 * 86_400),
        ], capturedAt: now.addingTimeInterval(-60), source: "from Claude Code's status line"))

        var codexLedger = UsageLedger()
        codexLedger.merge(events(prefix: "c", models: [("gpt-5.5-codex", 1)], projects: ["raboj", "scripts"], dailyTokens: 9_000_000))
        codexLedger.offer(plan: PlanSnapshot(windows: [
            PlanWindow(id: "primary", title: "Current session", usedPercent: 12, resetsAt: now.addingTimeInterval(4 * 3_600), length: 5 * 3_600),
            PlanWindow(id: "secondary", title: "This week", usedPercent: 9, resetsAt: now.addingTimeInterval(6 * 86_400), length: 7 * 86_400),
        ], capturedAt: now.addingTimeInterval(-300), source: "from Codex's own logs"))

        var routerLedger = UsageLedger()
        routerLedger.merge(events(prefix: "o", models: [("deepseek-v4", 0.5), ("gemini-3-flash", 0.5)], projects: ["bot"], dailyTokens: 0, cost: 1.9).map {
            UsageEvent(key: $0.key, timestamp: $0.timestamp, model: $0.model, tokens: .zero, costUSD: $0.costUSD, project: $0.project)
        })

        ledgers = [personal.id: personalLedger, work.id: workLedger, codex.id: codexLedger, openRouter.id: routerLedger]
    }

    func model() -> AppModel {
        AppModel(demoAccounts: [personal, work, codex, openRouter], ledgers: ledgers, now: now)
    }
}

/// Deterministic random numbers so screenshots are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
