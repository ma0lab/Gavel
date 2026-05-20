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

    static func projectBreakdown(items: [ActivityItem], limit: Int = 8) -> [ProjectStat] {
        let grouped = Dictionary(grouping: items) {
            $0.workingDirectory ?? "__unknown__"
        }
        let stats = grouped.map { path, items -> ProjectStat in
            let name = path == "__unknown__" ? "(unknown)"
                     : (path as NSString).lastPathComponent
            return ProjectStat(id: path, name: name, count: items.count)
        }.sorted { $0.count > $1.count }

        guard stats.count > limit else { return stats }
        let top = Array(stats.prefix(limit))
        let otherCount = stats.dropFirst(limit).reduce(0) { $0 + $1.count }
        return top + [ProjectStat(id: "__other__", name: "Other", count: otherCount)]
    }
}
