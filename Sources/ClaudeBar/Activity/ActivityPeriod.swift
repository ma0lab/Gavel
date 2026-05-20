import Foundation

enum ActivityPeriod: String, CaseIterable, Identifiable {
    case day   = "日"
    case week  = "週"
    case month = "月"

    var id: String { rawValue }

    var bucketCount: Int {
        switch self {
        case .day:   return 30
        case .week:  return 12
        case .month: return 12
        }
    }

    var rangeStart: Date {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .day:
            return cal.date(byAdding: .day, value: -(bucketCount - 1), to: cal.startOfDay(for: now))!
        case .week:
            let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return cal.date(byAdding: .weekOfYear, value: -(bucketCount - 1), to: weekStart)!
        case .month:
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            return cal.date(byAdding: .month, value: -(bucketCount - 1), to: monthStart)!
        }
    }

    func bucketDate(for date: Date) -> Date {
        let cal = Calendar.current
        switch self {
        case .day:
            return cal.startOfDay(for: date)
        case .week:
            return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date))!
        case .month:
            return cal.date(from: cal.dateComponents([.year, .month], from: date))!
        }
    }

    func allBucketDates() -> [Date] {
        let cal = Calendar.current
        let start = rangeStart
        return (0..<bucketCount).map { i in
            switch self {
            case .day:   return cal.date(byAdding: .day,        value: i, to: start)!
            case .week:  return cal.date(byAdding: .weekOfYear, value: i, to: start)!
            case .month: return cal.date(byAdding: .month,      value: i, to: start)!
            }
        }
    }

    func label(for date: Date) -> String {
        let fmt = DateFormatter()
        switch self {
        case .day:
            fmt.dateFormat = "M/d"
        case .week:
            fmt.dateFormat = "M/d"
        case .month:
            fmt.dateFormat = "M月"
        }
        return fmt.string(from: date)
    }
}
