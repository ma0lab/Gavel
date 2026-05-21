import Foundation

struct TodaySummary {
    let allow: Int
    let deny: Int
    let sessions: Int
    var total: Int { allow + deny }
}

struct StatBucket: Identifiable {
    let id: Date
    let label: String
    let allow: Int
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
        TodaySummary(
            allow:    items.filter { $0.decision == .allow }.count,
            deny:     items.filter { $0.decision == .deny  }.count,
            sessions: Set(items.compactMap { $0.sessionId }).count
        )
    }

    static func buckets(items: [ActivityItem], period: ActivityPeriod) -> [StatBucket] {
        let start = period.rangeStart
        let grouped = Dictionary(grouping: items.filter { $0.timestamp >= start }) {
            period.bucketDate(for: $0.timestamp)
        }
        return period.allBucketDates().map { date in
            let bucket = grouped[date] ?? []
            return StatBucket(
                id: date,
                label: period.label(for: date),
                allow: bucket.filter { $0.decision == .allow }.count,
                deny:  bucket.filter { $0.decision == .deny  }.count
            )
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
            let bucket = grouped[date] ?? []
            return StatBucket(id: date, label: fmt.string(from: date),
                              allow: bucket.filter { $0.decision == .allow }.count,
                              deny:  bucket.filter { $0.decision == .deny  }.count)
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

        func summarize(_ from: Date, _ to: Date) -> (allow: Int, deny: Int) {
            let slice = items.filter { $0.timestamp >= from && $0.timestamp < to }
            return (allow: slice.filter { $0.decision == .allow }.count,
                    deny:  slice.filter { $0.decision == .deny  }.count)
        }
        let cur  = summarize(curFrom, curTo)
        let prev = summarize(prevFrom, prevTo)
        return PeriodComparison(
            stat: ComparisonStat(currentAllow: cur.allow, currentDeny: cur.deny,
                                 previousAllow: prev.allow, previousDeny: prev.deny),
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
