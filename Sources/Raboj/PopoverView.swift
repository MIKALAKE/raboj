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
                return (account?.label ?? "?", Color(nsColor: account?.color.nsColor ?? .gray), "\(account?.label ?? "") · \(account?.provider.displayName ?? "")")
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
            ForEach(included) { account in
                Button { model.selection = .account(account.id) } label: { row(account) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var included: [Account] { model.accounts.filter(\.includeInAll) }

    private func row(_ account: Account) -> some View {
        let ledger = model.ledger(account.id)
        let plan = ledger.plan?.activeWindows(now: model.now).max { $0.usedPercent < $1.usedPercent }
        let today = ledger.summary(.today, now: model.now)
        let maxTokens = included.map { model.ledger($0.id).summary(.today, now: model.now).tokens.total }.max() ?? 0
        let fraction: Double = plan.map { $0.usedPercent / 100 } ?? (maxTokens > 0 ? Double(today.tokens.total) / Double(maxTokens) : 0)
        let note: String = {
            if let error = model.status(account.id).error { return error }
            if let plan, let reset = plan.resetsAt { return "\(plan.title) · resets in \(Format.countdown(to: reset, now: model.now))" }
            if let cost = ledger.summary(.month, now: model.now).cost, account.provider.headline == .cost { return "\(Format.usd(cost)) in the last 30 days" }
            return "\(Format.tokens(today.tokens.total)) tokens today"
        }()
        let color = Color(nsColor: account.color.nsColor)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(account.label).fontWeight(.semibold)
                Text(account.provider.displayName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(model.headline(account)).fontWeight(.bold)
            }
            ProgressBar(fraction: fraction, color: color, height: 5)
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
        let color = Color(nsColor: account.color.nsColor)
        let status = model.status(account.id)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(account.provider.displayName)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
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
                Text(bigNumber(summary)).font(.system(size: 32, weight: .bold))
                Text(account.provider.headline == .cost ? "billed" : "tokens").foregroundStyle(.secondary)
                Spacer()
                if let change = summary.change {
                    Text("\(Format.change(change)) vs \(summary.changeBaseline)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(window.title).font(.caption)
                                Spacer()
                                Text("\(Format.percent(window.usedPercent)) used").font(.caption.weight(.semibold))
                                if let reset = window.resetsAt {
                                    Text("· resets in \(Format.countdown(to: reset, now: model.now))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            ProgressBar(fraction: window.usedPercent / 100, color: color, height: 7)
                        }
                    }
                }
            } else if account.provider == .claudeCode {
                if let window = ledger.currentWindow(now: model.now) {
                    Card {
                        HStack { Text("Current 5-hour window").font(.caption.weight(.semibold)); Spacer(); Text("estimate from your logs").font(.caption2).foregroundStyle(.secondary) }
                        ProgressBar(fraction: window.elapsedFraction(now: model.now), color: color, height: 6)
                        Text("\(Format.tokens(window.tokens)) tokens · since \(window.start.formatted(date: .omitted, time: .shortened)), ends ~\(window.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Show real plan limits…") { WindowCoordinator.shared.openSettings(tab: .accounts, account: account.id) }
                    .buttonStyle(.link).font(.caption)
            }

            if account.provider.headline == .tokens || summary.tokens.total > 0 {
                TokenSplit(tokens: summary.tokens, color: color)
            }

            WeekChart(days: ledger.daily(days: 7, now: model.now), color: color, useCost: account.provider.headline == .cost)

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
        return "Official Admin API · key in Keychain"
    }

    private func bigNumber(_ summary: UsageSummary) -> String {
        account.provider.headline == .cost ? Format.usd(summary.cost ?? 0) : Format.tokens(summary.tokens.total)
    }
}

// MARK: - Small building blocks

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
    let useCost: Bool

    var body: some View {
        let values = days.map { useCost ? $0.cost : Double($0.tokens) }
        let maxValue = max(values.max() ?? 0, 0.000_1)
        let total = values.reduce(0, +)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Last 7 days").font(.caption.weight(.semibold))
                Spacer()
                Text(useCost ? Format.usd(total) : Format.tokens(Int(total)) + " tokens").font(.caption).foregroundStyle(.secondary)
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
