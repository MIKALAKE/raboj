import RabojCore
import SwiftUI

@main
struct RabojApp: App {
    var body: some Scene {
        MenuBarExtra {
            PopoverPlaceholder()
        } label: {
            Image(systemName: "chart.bar.fill")
                .accessibilityLabel("Răboj")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Temporary content until the real popover lands (milestone M3).
private struct PopoverPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Răboj")
                .font(.headline)
            Text("Supported providers: \(Provider.allCases.map(\.displayName).joined(separator: ", "))")
                .font(.callout)
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit Răboj") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }
}
