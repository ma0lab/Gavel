import Foundation

struct TodaySummary {
    let allow: Int
    let autoAllow: Int
    let deny: Int
    let sessions: Int
    var total: Int { allow + deny }
}

struct StatBucket: Identifiable {
    let id: Date
    let label: String
    let allow: Int
    let autoAllow: Int
    let deny: Int
    var total: Int { allow + deny }
}

struct PeriodComparison {
    let stat: ComparisonStat
    let currentLabel: String
    let previousLabel: String
}

struct ComparisonStat: Equatable {
    let currentAllow: Int
    let currentDeny:  Int
    let previousAllow: Int
    let previousDeny:  Int
    var currentTotal:  Int { currentAllow + currentDeny }
    var previousTotal: Int { previousAllow + previousDeny }
    var delta: Int { currentTotal - previousTotal }
    var deltaPercent: Double {
        previousTotal == 0 ? 0 : Double(delta) / Double(previousTotal) * 100
    }
}

struct ProjectStat: Identifiable {
    let id: String
    let name: String
    let count: Int
}

enum ActivityStats {
    static func todaySummary(items: [ActivityItem]) -> TodaySummary {
        let (allow, autoAllow, deny) = items.decisionCounts
        let sessions = Set(items.compactMap { $0.sessionId }).count
        return TodaySummary(allow: allow, autoAllow: autoAllow, deny: deny, sessions: sessions)
    }

    static func buckets(items: [ActivityItem], period: ActivityPeriod) -> [StatBucket] {
        let start = period.rangeStart
        let grouped = Dictionary(grouping: items.filter { $0.timestamp >= start }) {
            period.bucketDate(for: $0.timestamp)
        }
        return period.allBucketDates().map { date in
            StatBucket(id: date, label: period.label(for: date),
                       counts: grouped[date] ?? [])
        }
    }

    static func buckets(items: [ActivityItem], from: Date, to: Date) -> [StatBucket] {
        let cal = Calendar.current
        let endDay = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: to)!)
        let grouped = Dictionary(grouping: items.filter {
            $0.timestamp >= from && $0.timestamp < endDay
        }) { cal.startOfDay(for: $0.timestamp) }

        var dates: [Date] = []
        var d = cal.startOfDay(for: from)
        let lastDay = cal.startOfDay(for: to)
        while d <= lastDay {
            dates.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        let fmt = DateFormatter(); fmt.dateFormat = "M/d"
        return dates.map { date in
            StatBucket(id: date, label: fmt.string(from: date),
                       counts: grouped[date] ?? [])
        }
    }

    static func comparisonStats(items: [ActivityItem], period: ActivityPeriod,
                                customStart: Date = Date(), customEnd: Date = Date()) -> PeriodComparison {
        let cal = Calendar.current
        let now = Date()
        let curFrom, curTo, prevFrom, prevTo: Date
        let curLabel, prevLabel: String

        switch period {
        case .day:
            let todayStart = cal.startOfDay(for: now)
            let yestStart  = cal.date(byAdding: .day, value: -1, to: todayStart)!
            (curFrom, curTo)   = (todayStart, now)
            (prevFrom, prevTo) = (yestStart, todayStart)
            (curLabel, prevLabel) = ("Today", "Yesterday")
        case .week:
            let weekStart     = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
            (curFrom, curTo)   = (weekStart, now)
            (prevFrom, prevTo) = (lastWeekStart, weekStart)
            (curLabel, prevLabel) = ("This Week", "Last Week")
        case .month:
            let monthStart     = cal.date(from: cal.dateComponents([.year, .month], from: now))!
            let lastMonthStart = cal.date(byAdding: .month, value: -1, to: monthStart)!
            (curFrom, curTo)   = (monthStart, now)
            (prevFrom, prevTo) = (lastMonthStart, monthStart)
            (curLabel, prevLabel) = ("This Month", "Last Month")
        case .custom:
            let duration = max(customEnd.timeIntervalSince(customStart), 86400)
            (curFrom, curTo)   = (customStart, customEnd)
            (prevFrom, prevTo) = (customStart.addingTimeInterval(-duration), customStart)
            (curLabel, prevLabel) = ("Custom", "Prior")
        }

        var curAllow = 0, curDeny = 0, prevAllow = 0, prevDeny = 0
        for item in items {
            let t = item.timestamp
            if t >= curFrom && t < curTo {
                if item.decision == .allow { curAllow += 1 }
                else if item.decision == .deny { curDeny += 1 }
            } else if t >= prevFrom && t < prevTo {
                if item.decision == .allow { prevAllow += 1 }
                else if item.decision == .deny { prevDeny += 1 }
            }
        }
        return PeriodComparison(
            stat: ComparisonStat(currentAllow: curAllow, currentDeny: curDeny,
                                 previousAllow: prevAllow, previousDeny: prevDeny),
            currentLabel: curLabel,
            previousLabel: prevLabel
        )
    }

    static func projectBreakdown(items: [ActivityItem], limit: Int = 8) -> [ProjectStat] {
        let grouped = Dictionary(grouping: items) {
            $0.workingDirectory ?? "__unknown__"
        }
        let stats = grouped.map { path, items -> ProjectStat in
            let name = path == "__unknown__" ? "(unknown)" : path.projectName
            return ProjectStat(id: path, name: name, count: items.count)
        }.sorted { $0.count > $1.count }

        guard stats.count > limit else { return stats }
        let top = Array(stats.prefix(limit))
        let otherCount = stats.dropFirst(limit).reduce(0) { $0 + $1.count }
        return top + [ProjectStat(id: "__other__", name: "Other", count: otherCount)]
    }
}

private extension Array where Element == ActivityItem {
    var decisionCounts: (allow: Int, autoAllow: Int, deny: Int) {
        reduce(into: (0, 0, 0)) { acc, item in
            if item.decision == .allow { acc.0 += 1 }
            if item.isAutoAllowed      { acc.1 += 1 }
            if item.decision == .deny  { acc.2 += 1 }
        }
    }
}

private extension StatBucket {
    init(id: Date, label: String, counts: [ActivityItem]) {
        let (allow, autoAllow, deny) = counts.decisionCounts
        self.init(id: id, label: label, allow: allow, autoAllow: autoAllow, deny: deny)
    }
}
