import AppKit
import RabojCore
import SwiftUI

/// A provider's logo drawn from its SVG path, or a monogram badge when no freely licensed logo exists.
struct ProviderLogoView: View {
    let provider: Provider
    var size: CGFloat = 20

    var body: some View {
        if let logo = provider.logo {
            LogoShape(svg: logo.path)
                .fill(Self.color(logo.hex))
                .frame(width: size, height: size)
                .accessibilityLabel("\(provider.displayName) logo")
        } else {
            Text(provider.monogram)
                .font(.system(size: size * (provider.monogram.count > 2 ? 0.34 : 0.42), weight: .bold, design: .rounded))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.25).fill(Color.primary.opacity(0.12)))
                .accessibilityLabel(provider.displayName)
        }
    }

    /// Near-black brand colors would vanish in dark mode, so they follow the text color instead.
    static func color(_ hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF), g = Double((hex >> 8) & 0xFF), b = Double(hex & 0xFF)
        let luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255
        return luminance < 0.2 ? .primary : Color(nsColor: NSColor(hex: hex))
    }
}

private struct LogoShape: Shape {
    let svg: String

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        var transform = CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: scale, y: scale)
        guard let scaled = SVGPath.cgPath(svg).copy(using: &transform) else { return Path() }
        return Path(scaled)
    }
}

/// Row of colored circles; the selected one gets a ring. Replaces a menu picker, whose items lose their color.
struct ColorSwatchPicker: View {
    @Binding var selection: AccountColor

    var body: some View {
        HStack(spacing: 10) {
            ForEach(AccountColor.allCases, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    Circle()
                        .fill(Color(nsColor: option.nsColor))
                        .frame(width: 20, height: 20)
                        .padding(3)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(selection == option ? 0.85 : 0), lineWidth: 2))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
    }
}
