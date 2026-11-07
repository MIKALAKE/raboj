import Foundation
import RabojCore

/// `Raboj --report claude|codex <folder>`: prints what Răboj would show for a folder, without the UI.
/// Useful to check numbers and to debug log-format changes.
enum Report {
    static func run(_ arguments: [String]) {
        guard arguments.count >= 2, let provider = ["claude": Provider.claudeCode, "codex": Provider.codex][arguments[0]] else {
            print("usage: Raboj --report claude|codex <folder>")
            return
        }
        let root = URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath)
        let started = Date()
        let result = FolderReader(provider: provider, root: root, accessing: false).readNow()
        if let error = result.error { print("error: \(error)"); return }
        var ledger = UsageLedger()
        ledger.merge(result.events)
        ledger.offer(plan: result.plan)
        let now = Date()
        print("\(provider.displayName) · \(root.path)")
        print("read \(result.events.count) usage lines → \(ledger.events.count) unique in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
        for period in Period.allCases {
            let summary = ledger.summary(period, now: now)
            let t = summary.tokens
            let change = summary.change.map { " (\(Format.change($0)) vs \(summary.changeBaseline))" } ?? ""
            print("\(period.title.padding(toLength: 8, withPad: " ", startingAt: 0)) \(Format.tokens(t.total)) tokens\(change) · in \(Format.tokens(t.input)) out \(Format.tokens(t.output)) cache-w \(Format.tokens(t.cacheWrite)) cache-r \(Format.tokens(t.cacheRead))")
        }
        let month = ledger.summary(.month, now: now)
        print("models (30d): " + month.byModel.prefix(4).map { "\($0.name) \(Format.percent($0.share * 100))" }.joined(separator: ", "))
        if let window = ledger.currentWindow(now: now) {
            print("5-hour window (estimate): \(Format.tokens(window.tokens)) since \(window.start.formatted(date: .omitted, time: .shortened))")
        }
        if let plan = ledger.plan {
            for window in plan.windows {
                let reset = window.resetsAt.map { " · resets in \(Format.countdown(to: $0, now: now))" } ?? ""
                print("plan: \(window.title) \(Format.percent(window.usedPercent)) used\(reset) (\(plan.source), captured \(plan.capturedAt.formatted()))")
            }
        }
    }
}
