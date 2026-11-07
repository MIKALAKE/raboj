import Foundation

public enum Format {
    /// 980 → "980", 12_345 → "12.3K", 640_000 → "640K", 2_410_000 → "2.41M".
    public static func tokens(_ value: Int) -> String {
        let v = Double(value)
        switch abs(v) {
        case ..<1_000: return "\(value)"
        case ..<1_000_000: return compact(v / 1_000) + "K"
        case ..<1_000_000_000: return compact(v / 1_000_000) + "M"
        default: return compact(v / 1_000_000_000) + "B"
        }
    }

    private static func compact(_ v: Double) -> String {
        let digits = v >= 100 ? 0 : (v >= 10 ? 1 : 2)
        var text = String(format: "%.\(digits)f", v)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// 4.1 → "$4.10", 1234.5 → "$1,234.50".
    public static func usd(_ value: Double) -> String {
        value.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
    }

    /// 0.34 → "+34%", -0.05 → "−5%".
    public static func change(_ value: Double) -> String {
        let percent = Int((value * 100).rounded())
        return percent >= 0 ? "+\(percent)%" : "−\(abs(percent))%"
    }

    /// 31.4 → "31%".
    public static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    /// Time until a date: "2d 4h", "3h 05m", "12m".
    public static func countdown(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3_600, minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return String(format: "%dh %02dm", hours, minutes) }
        return "\(minutes)m"
    }
}
