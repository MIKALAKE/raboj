import RabojCore
import SwiftUI

struct PopoverView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if model.accounts.isEmpty {
                EmptyStateView()
            } else {
                AccountSwitcher()
                switch model.selection {
                case .all:
                    AllAccountsView()
                case .account(let id):
                    if let account = model.account(id) { AccountDetailView(account: account) } else { AllAccountsView() }
                }
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
        .monospacedDigit()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: TallyIcon.image(size: 18))
            Text("Răboj").font(.headline)
            Spacer()
            Button { WindowCoordinator.shared.openAddAccount() } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless)
                .help("Add account")
                .accessibilityLabel("Add account")
            Button { WindowCoordinator.shared.openSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Settings")
                .keyboardShortcut(",", modifiers: .command)
        }
    }

    private var footer: some View {
        HStack {
            Text(updatedText).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Refresh") { model.refreshAll() }.buttonStyle(.borderless).font(.caption).keyboardShortcut("r", modifiers: .command)
            Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless).font(.caption).keyboardShortcut("q", modifiers: .command)
        }
    }

    private var updatedText: String {
        let dates = model.accounts.compactMap { model.status($0.id).lastUpdated }
        guard let latest = dates.max() else { return "Not updated yet" }
        return "Updated " + latest.formatted(date: .omitted, time: .shortened)
    }
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No accounts yet").font(.title3.weight(.semibold))
            Text("Add a Claude Code or Codex folder, or an Anthropic or OpenAI admin key. You can add as many accounts as you like.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add your first account") { WindowCoordinator.shared.openAddAccount() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }
}

/// All + one chip per account. ⌘0 is All, ⌘1 … ⌘9 the accounts in order.
private struct AccountSwitcher: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(model.selectionOrder.enumerated()), id: \.offset) { index, selection in
                    chip(for: selection, index: index)
                }
            }
            .padding(3)
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.07)))
    }

    @ViewBuilder
    private func chip(for selection: Selection, index: Int) -> some View {
        let isOn = model.selection == selection
        let (label, color, help): (String, Color, String) = {
            switch selection {
            case .all: return ("All", .secondary, "All accounts")
            case .account(let id):
                let account = model.account(id)
                return (account?.label ?? "?", Color(nsColor: account?.nsColor ?? .gray), "\(account?.label ?? "") · \(account?.provider.displayName ?? "")")
            }
        }()
        let button = Button {
            model.selection = selection
        } label: {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(label).lineLimit(1)
            }
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(isOn ? Color(nsColor: .controlBackgroundColor) : .clear).shadow(color: .black.opacity(isOn ? 0.12 : 0), radius: 1, y: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(index <= 9 ? "\(help) (⌘\(index))" : help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        if index <= 9 {
            button.keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
        } else {
            button
        }
    }
}

private struct AllAccountsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("All accounts · today").font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(included.count) accounts").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Show", selection: $model.allMetric) {
                ForEach(model.availableMetrics) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("What each account shows here and in the menu bar")
            ForEach(included) { account in
                Button { model.selection = .account(account.id) } label: { row(account) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var included: [Account] { model.accounts.filter(\.includeInAll) }

    /// Number behind the bar, so bars compare accounts on the chosen metric.
    private func amount(_ account: Account) -> Double {
        let today = model.ledger(account.id).summary(.today, now: model.now)
        switch model.allMetric {
        case .auto, .tokens: return Double(today.tokens.total)
        case .cost: return today.cost ?? 0
        case .requests: return Double(today.requests)
        case .limits: return 0
        }
    }

    private func row(_ account: Account) -> some View {
        let ledger = model.ledger(account.id)
        let value = model.value(account, metric: model.allMetric)
        let largest = included.map(amount).max() ?? 0
        let relative = largest > 0 ? amount(account) / largest : 0
        let fraction = value.fraction ?? (value.text == "—" ? 0 : relative)
        let note: String = {
            if let error = model.status(account.id).error { return error }
            if model.allMetric != .auto { return value.note }
            if let plan = ledger.plan?.activeWindows(now: model.now).max(by: { $0.usedPercent < $1.usedPercent }), let reset = plan.resetsAt {
                return "\(plan.title) · resets in \(Format.countdown(to: reset, now: model.now))"
            }
            let today = ledger.summary(.today, now: model.now)
            switch account.provider.headline {
            case .cost: return "\(Format.usd(ledger.summary(.month, now: model.now).cost ?? 0)) in the last 30 days"
            case .requests: return "\(ledger.summary(.month, now: model.now).requests) requests in the last 30 days"
            case .balance: return ledger.info.first?.title ?? "Balance"
            case .tokens: return "\(Format.tokens(today.tokens.total)) tokens today"
            }
        }()
        let color = Color(nsColor: account.nsColor)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 9, height: 9)
                ProviderLogoView(provider: account.provider, size: 14)
                Text(account.label).fontWeight(.semibold).lineLimit(1)
                Text(account.provider.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(value.text).fontWeight(.bold).foregroundStyle(value.text == "—" ? Color.secondary : Color.primary)
            }
            ProgressBar(fraction: fraction, color: (value.fraction ?? 0) >= 0.9 ? .orange : color, height: 5)
            Text(note).font(.caption).foregroundStyle(model.status(account.id).error == nil ? Color.secondary : Color.orange).lineLimit(1)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
        .contentShape(Rectangle())
    }
}

struct AccountDetailView: View {
    @EnvironmentObject private var model: AppModel
    let account: Account

    var body: some View {
        let ledger = model.ledger(account.id)
        let summary = ledger.summary(model.period, now: model.now)
        let color = Color(nsColor: account.nsColor)
        let status = model.status(account.id)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ProviderLogoView(provider: account.provider, size: 16)
                Text(account.provider.displayName)
                    .font(.caption.weight(.semibold))
                Text(sourceText).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }

            Picker("Period", selection: $model.period) {
                ForEach(Period.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let error = status.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            } else if status.loading && ledger.isEmpty {
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Reading usage…").font(.caption).foregroundStyle(.secondary) }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bigNumber(summary, ledger: ledger)).font(.system(size: 32, weight: .bold))
                Text(unitLabel).foregroundStyle(.secondary)
                Spacer()
                if let change = summary.change {
                    Text("\(Format.change(change)) vs \(summary.changeBaseline)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }

            if !ledger.info.isEmpty {
                Card {
                    ForEach(ledger.info) { item in
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.title).font(.caption)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(item.value).font(.caption.weight(.semibold))
                                if let detail = item.detail, !detail.isEmpty { Text(detail).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }

            if let plan = ledger.plan, !plan.activeWindows(now: model.now).isEmpty {
                Card {
                    HStack {
                        Text("Plan limits").font(.caption.weight(.semibold))
                        Spacer()
                        Text(planSourceText(plan)).font(.caption2).foregroundStyle(.secondary)
                    }
                    ForEach(plan.activeWindows(now: model.now)) { window in
                        PlanWindowRow(window: window, color: color, now: model.now)
                    }
                }
            } else if account.provider == .claudeCode {
                Card {
                    Text("See your session and weekly limits").font(.caption.weight(.semibold))
                    Text("The same numbers as /usage in Claude Code. One-time setup: paste one line into Claude Code’s settings.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Set Up…") { WindowCoordinator.shared.openSettings(tab: .accounts, account: account.id) }
                        .controlSize(.small)
                }
                if let window = ledger.currentWindow(now: model.now) {
                    Card {
                        HStack { Text("Activity on this Mac, last 5 hours").font(.caption.weight(.semibold)); Spacer(); Text("not your plan %").font(.caption2).foregroundStyle(.secondary) }
                        Text("\(Format.tokens(window.tokens)) tokens since \(window.start.formatted(date: .omitted, time: .shortened)). Your plan also counts claude.ai, the desktop app and other devices, so its session can start earlier and its % differs.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if summary.tokens.total > 0 {
                TokenSplit(tokens: summary.tokens, color: color)
            }

            if account.provider.headline != .balance {
                WeekChart(days: ledger.daily(days: 7, now: model.now), color: color, metric: account.provider.headline)
            }

            HStack(alignment: .top, spacing: 16) {
                ShareList(title: "By model", items: summary.byModel)
                if !summary.byProject.isEmpty { ShareList(title: "By project", items: summary.byProject) }
            }
        }
    }

    /// The provider only reports limits when the tool is used, so say how old the numbers are.
    private func planSourceText(_ plan: PlanSnapshot) -> String {
        let age = model.now.timeIntervalSince(plan.capturedAt)
        guard age > 3_600 else { return plan.source }
        let when = age > 86_400 ? plan.capturedAt.formatted(date: .abbreviated, time: .omitted) : plan.capturedAt.formatted(date: .omitted, time: .shortened)
        return "\(plan.source) · as of \(when)"
    }

    private var sourceText: String {
        if let path = account.folderPath { return "Local logs · " + FolderAccess.displayPath(path) }
        return "Official API · key in Keychain"
    }

    private var unitLabel: String {
        switch account.provider.headline {
        case .tokens: "tokens"
        case .cost: "billed"
        case .requests: "requests"
        case .balance: "balance"
        }
    }

    private func bigNumber(_ summary: UsageSummary, ledger: UsageLedger) -> String {
        switch account.provider.headline {
        case .tokens: Format.tokens(summary.tokens.total)
        case .cost: Format.usd(summary.cost ?? 0)
        case .requests: "\(summary.requests)"
        case .balance: ledger.info.first?.value ?? "—"
        }
    }
}

// MARK: - Small building blocks

/// One plan window, laid out like Claude Code's /usage: name, reset time, bar, percent and where it is heading.
struct PlanWindowRow: View {
    let window: PlanWindow
    let color: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.callout.weight(.semibold))
                Spacer()
                Text("\(Format.percent(window.usedPercent)) used").font(.callout.weight(.semibold)).foregroundStyle(barColor)
            }
            ProgressBar(fraction: window.usedPercent / 100, color: barColor, height: 7)
            HStack {
                if let reset = window.resetsAt {
                    Text("Resets \(Self.resetText(reset, now: now)) · in \(Format.countdown(to: reset, now: now))")
                }
                Spacer()
                if let pace = paceText { Text(pace).foregroundStyle(paceIsBad ? Color.orange : Color.secondary) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var pace: PlanWindow.Pace? { window.pace(now: now) }

    private var paceIsBad: Bool {
        switch pace {
        case .willHitLimit, .limitReached: true
        default: false
        }
    }

    private var barColor: Color { paceIsBad || window.usedPercent >= 90 ? .orange : color }

    private var paceText: String? {
        switch pace {
        case .onTrack(let projected): "On track · ~\(Format.percent(projected)) by reset"
        case .willHitLimit(let at): "Limit around \(at.formatted(date: .omitted, time: .shortened))"
        case .limitReached: "Limit reached"
        case nil: nil
        }
    }

    /// "at 03:30" today, "tomorrow at 01:00", else "Mon 01:00".
    static func resetText(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "tomorrow at \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08)))
    }
}

struct ProgressBar: View {
    var fraction: Double
    var color: Color
    var height: CGFloat
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Format.percent(fraction * 100))
    }
}

private struct TokenSplit: View {
    let tokens: TokenCounts
    let color: Color

    var body: some View {
        let parts: [(String, Int, Double)] = [
            ("Input", tokens.input, 1), ("Output", tokens.output, 0.75),
            ("Cache write", tokens.cacheWrite, 0.45), ("Cache read", tokens.cacheRead, 0.22),
        ]
        let total = max(1, tokens.total)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { part in
                        Rectangle().fill(color.opacity(part.2)).frame(width: max(0, proxy.size.width * Double(part.1) / Double(total) - 2))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 4) {
                ForEach(parts, id: \.0) { part in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(color.opacity(part.2)).frame(width: 8, height: 8)
                        Text(part.0).foregroundStyle(.secondary)
                        Spacer()
                        Text(Format.tokens(part.1)).fontWeight(.semibold)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

private struct WeekChart: View {
    let days: [DayTotal]
    let color: Color
    let metric: Headline

    private func value(_ day: DayTotal) -> Double {
        switch metric {
        case .cost: day.cost
        case .requests: Double(day.requests)
        case .tokens, .balance: Double(day.tokens)
        }
    }

    private func label(_ total: Double) -> String {
        switch metric {
        case .cost: Format.usd(total)
        case .requests: "\(Int(total)) requests"
        case .tokens, .balance: Format.tokens(Int(total)) + " tokens"
        }
    }

    var body: some View {
        let values = days.map(value)
        let maxValue = max(values.max() ?? 0, 0.000_1)
        let total = values.reduce(0, +)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Last 7 days").font(.caption.weight(.semibold))
                Spacer()
                Text(label(total)).font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(index == days.count - 1 ? 1 : 0.65))
                            .frame(height: max(2, 56 * values[index] / maxValue))
                        Text(day.day.formatted(.dateTime.weekday(.abbreviated))).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 72, alignment: .bottom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Usage per day, last 7 days")
        }
    }
}

private struct ShareList: View {
    let title: String
    let items: [NamedShare]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            if items.isEmpty {
                Text("No usage").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(items.prefix(3)) { item in
                HStack {
                    Text(item.name).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(Format.percent(item.share * 100)).fontWeight(.semibold)
                }
                .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
