import Foundation

/// Relative timestamp shown under a user bubble — a 1:1 port of the web transcript's `relTime`:
/// "just now", "5m ago", "3h ago", "2d ago", "1w ago"; older than ~4 weeks falls back to a short
/// absolute month/day. Pure (now is injectable) so it's deterministic in tests.
public enum RelativeTime {
    public static func format(_ iso: String, now: Date = Date()) -> String? {
        guard let date = parse(iso) else { return nil }
        let diff = now.timeIntervalSince(date)
        let min = 60.0, hour = 3600.0, day = 86_400.0, week = 604_800.0
        if diff < min  { return "just now" }
        if diff < hour { return "\(Int(diff / min))m ago" }
        if diff < day  { return "\(Int(diff / hour))h ago" }
        if diff < week { return "\(Int(diff / day))d ago" }
        if diff < 4 * week { return "\(Int(diff / week))w ago" }
        let fmt = DateFormatter()
        fmt.dateFormat = "M/d"
        return fmt.string(from: date)
    }

    /// ISO-8601 from the runner — try with then without fractional seconds (some payloads omit it).
    private static func parse(_ iso: String) -> Date? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = parser.date(from: iso) { return d }
        parser.formatOptions = [.withInternetDateTime]
        return parser.date(from: iso)
    }
}
