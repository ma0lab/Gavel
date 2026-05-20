import SwiftUI
import Charts

struct StatsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var period: ActivityPeriod = .day
    @State private var buckets: [StatBucket] = []
    @State private var projects: [ProjectStat] = []

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            VStack(spacing: 0) {
                periodPicker
                barChart
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
            }
            Divider()
            projectBreakdown
        }
        .onAppear { reload() }
        .onChange(of: period) { reload() }
    }

    // MARK: - Today summary

    private var summaryHeader: some View {
        HStack(spacing: 0) {
            summaryCell(label: "Today", value: "\(state.todaySummary.total)", color: .primary)
            Divider().frame(height: 44)
            summaryCell(label: "Allowed", value: "\(state.todaySummary.allow)", color: .green)
            Divider().frame(height: 44)
            summaryCell(label: "Denied", value: "\(state.todaySummary.deny)", color: .red)
            Divider().frame(height: 44)
            summaryCell(label: "Sessions", value: "\(state.todaySummary.sessions)", color: .blue)
        }
        .padding(.vertical, 18)
    }

    private func summaryCell(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Chart

    private var periodPicker: some View {
        Picker("", selection: $period) {
            ForEach(ActivityPeriod.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var barChart: some View {
        Chart(buckets) { bucket in
            BarMark(x: .value("Date", bucket.label), y: .value("Count", bucket.allow))
                .foregroundStyle(by: .value("Type", "Allow"))
            BarMark(x: .value("Date", bucket.label), y: .value("Count", bucket.deny))
                .foregroundStyle(by: .value("Type", "Deny"))
        }
        .chartForegroundStyleScale([
            "Allow": Color.green.opacity(0.75),
            "Deny":  Color.red.opacity(0.75)
        ])
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: period == .day ? 7 : 6))
        }
        .chartLegend(.hidden)
        .frame(height: 140)
    }

    // MARK: - Project breakdown

    private var projectBreakdown: some View {
        let maxCount = projects.first?.count ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            Text("Projects")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(projects) { proj in
                        projectRow(proj, maxCount: maxCount)
                    }
                }
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func projectRow(_ proj: ProjectStat, maxCount: Int) -> some View {
        HStack(spacing: 10) {
            Text(proj.name)
                .font(.callout)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accentColor.opacity(0.65))
                    .frame(width: max(4, geo.size.width * CGFloat(proj.count) / CGFloat(maxCount)))
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 16)
            Text("\(proj.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
    }

    // MARK: - Data

    private func reload() {
        let items = ActivityStore.shared.fetchSince(period.rangeStart)
        buckets  = ActivityStats.buckets(items: items, period: period)
        projects = ActivityStats.projectBreakdown(items: items)
    }
}
