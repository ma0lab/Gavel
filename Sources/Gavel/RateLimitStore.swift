import Foundation
import Combine

struct RateLimitData: Equatable {
    var fiveHourPct: Double?
    var sevenDayPct: Double?
    var fiveHourResetsAt: Date?
    var sevenDayResetsAt: Date?

    var fiveHourValue: Double { fiveHourPct ?? 0 }
    var sevenDayValue: Double { sevenDayPct ?? 0 }

    var summaryText: String? {
        guard let f = fiveHourPct, let s = sevenDayPct else { return nil }
        return String(format: "5h: %d%% | 7d: %d%%", Int(f.rounded()), Int(s.rounded()))
    }
}

@MainActor
final class RateLimitStore: ObservableObject {
    static let shared = RateLimitStore()

    @Published private(set) var data = RateLimitData()

    private static let fileURL = URL(fileURLWithPath: "/tmp/gavel_ratelimits.json")
    private var timer: Timer?

    private init() {
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.load() }
        }
    }

    private func load() {
        guard let raw = try? Data(contentsOf: Self.fileURL),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return }

        var d = RateLimitData()
        if let fh = json["five_hour"] as? [String: Any] {
            d.fiveHourPct = fh["used_percentage"] as? Double
            if let epoch = fh["resets_at"] as? TimeInterval {
                d.fiveHourResetsAt = Date(timeIntervalSince1970: epoch)
            }
        }
        if let sd = json["seven_day"] as? [String: Any] {
            d.sevenDayPct = sd["used_percentage"] as? Double
            if let epoch = sd["resets_at"] as? TimeInterval {
                d.sevenDayResetsAt = Date(timeIntervalSince1970: epoch)
            }
        }
        if data != d { data = d }
    }
}
