import SwiftUI
import Charts

struct StatsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var period: ActivityPeriod = .day
    @State private var buckets: [StatBucket] = []
    @State private var projects: [ProjectStat] = []
    @State private var reloadTask: Task<Void, Never>?
    @State private var hideTooltipTask: Task<Void, Never>?
    @State private var showCustomPicker = false
    @State private var selectedBucket: StatBucket?
    @State private var tooltipBarX: CGFloat = 0
    @State private var customStart: Date = Calendar.current.date(byAdding: .day, value: -13, to: Date())!
    @State private var customEnd: Date = Date()
    @State private var comparison: PeriodComparison?

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            Divider()
            filterBar
            Divider()
            ScrollView {
                VStack(spacing: 14) {
                    chartCard
                    projectCard
                    if let comp = comparison {
                        comparisonCard(comp)
                    }
                }
                .padding(16)
            }
        }
        .onAppear { reload() }
        .onDisappear {
            hideTooltipTask?.cancel()
            reloadTask?.cancel()
        }
        .onChange(of: period) { _, newPeriod in
            selectedBucket = nil
            if newPeriod != .custom { reload() }
        }
        .sheet(isPresented: $showCustomPicker) {
            CustomRangePickerView(start: $customStart, end: $customEnd) {
                showCustomPicker = false
                reload()
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ZStack {
            periodPicker
                .opacity(period == .custom ? 0 : 1)
                .allowsHitTesting(period != .custom)

            customRangeBar
                .opacity(period == .custom ? 1 : 0)
                .allowsHitTesting(period == .custom)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.horizontal, 16)
        .animation(.easeInOut(duration: 0.18), value: period == .custom)
    }

    private var customRangeBar: some View {
        let fmt = Date.FormatStyle().month(.abbreviated).day().locale(Locale(identifier: "en_US"))
        return VStack(spacing: 5) {
            HStack {
                Button { showCustomPicker = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10, weight: .medium))
                        Text("\(customStart.formatted(fmt))  –  \(customEnd.formatted(fmt))")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { period = .day }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(4)
                        .background(.secondary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 1.5)
                .cornerRadius(0.75)
        }
    }

    // MARK: - Summary Header

    private var summaryHeader: some View {
        VStack(spacing: 6) {
            allowedHero
            HStack(spacing: 6) {
                KPICardView(icon: "bolt.fill",     label: "Total",    value: state.todaySummary.total,    accent: .primary,  compact: true)
                KPICardView(icon: "xmark.circle.fill", label: "Denied", value: state.todaySummary.deny,  accent: .red,      compact: true)
                KPICardView(icon: "terminal.fill",  label: "Sessions", value: state.todaySummary.sessions, accent: .blue,   compact: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private static let secondsSavedPerAutoAllow = 5

    private var allowedHero: some View {
        let autoAllow = state.todaySummary.autoAllow
        let saved = autoAllow * Self.secondsSavedPerAutoAllow
        let savedLabel = saved < 60 ? "~\(saved)s saved" : "~\(saved / 60) min saved"
        return ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allowed")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.4)
                    Text("\(state.todaySummary.allow)")
                        .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Color.primary)
                }
                if autoAllow > 0 {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(autoAllow) auto")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.teal)
                        Text(savedLabel)
                            .font(.system(size: 9))
                            .foregroundStyle(Color.teal.opacity(0.7))
                    }
                    .padding(.bottom, 4)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Color.green.opacity(0.12))
                    .offset(x: 4, y: 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Chart Card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            barChart
        }
        .padding(14)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ActivityPeriod.allCases.filter { $0 != .custom }) { p in
                Button { withAnimation(.easeInOut(duration: 0.2)) { period = p } } label: {
                    periodTabLabel(p)
                }
                .buttonStyle(.plain)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { period = .custom }
                showCustomPicker = true
            } label: {
                periodTabLabel(.custom)
            }
            .buttonStyle(.plain)
        }
    }

    private func periodTabLabel(_ p: ActivityPeriod) -> some View {
        VStack(spacing: 5) {
            Text(p.rawValue)
                .font(.system(size: 11, weight: period == p ? .semibold : .regular))
                .foregroundStyle(period == p ? Color.accentColor : .secondary)
                .padding(.horizontal, 14)
            Rectangle()
                .fill(period == p ? Color.accentColor : Color.clear)
                .frame(height: 1.5)
                .cornerRadius(0.75)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var axisDateFormat: Date.FormatStyle {
        let locale = Locale(identifier: "en_US")
        switch period {
        case .day, .week, .custom:
            return Date.FormatStyle().month(.abbreviated).day().locale(locale)
        case .month:
            return Date.FormatStyle().month(.abbreviated).year(.twoDigits).locale(locale)
        }
    }

    private var periodUnit: Calendar.Component {
        switch period {
        case .day, .custom: return .day
        case .week:         return .weekOfYear
        case .month:        return .month
        }
    }

    private var barChart: some View {
        let unit = periodUnit
        return Chart(buckets) { bucket in
            let manualAllow = bucket.allow - bucket.autoAllow
            BarMark(x: .value("Date", bucket.id, unit: unit), y: .value("Count", bucket.autoAllow))
                .foregroundStyle(LinearGradient(
                    colors: [Color.teal, Color.teal.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                ))
                .cornerRadius(3)
            BarMark(x: .value("Date", bucket.id, unit: unit), y: .value("Count", manualAllow))
                .foregroundStyle(LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                ))
                .cornerRadius(3)
            BarMark(x: .value("Date", bucket.id, unit: unit), y: .value("Count", bucket.deny))
                .foregroundStyle(LinearGradient(
                    colors: [.red, .red.opacity(0.45)],
                    startPoint: .top, endPoint: .bottom
                ))
                .cornerRadius(3)
            if let sel = selectedBucket, sel.id == bucket.id {
                RuleMark(x: .value("Date", sel.id, unit: unit))
                    .foregroundStyle(Color.primary.opacity(0.18))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .zIndex(-1)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel(format: axisDateFormat)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.secondary)
            }
        }
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        guard let frame = proxy.plotFrame else { selectedBucket = nil; return }
                        let plotRect = geo[frame]
                        switch phase {
                        case .active(let loc):
                            hideTooltipTask?.cancel()
                            hideTooltipTask = nil
                            let x = loc.x - plotRect.origin.x
                            guard x >= 0, x <= plotRect.width else {
                                hideTooltipTask = makeHideTask { selectedBucket = nil }
                                return
                            }
                            if let date: Date = proxy.value(atX: x) {
                                let hit = buckets.min(by: {
                                    abs($0.id.timeIntervalSince(date)) < abs($1.id.timeIntervalSince(date))
                                })
                                selectedBucket = hit
                                tooltipBarX = loc.x
                            }
                        case .ended:
                            hideTooltipTask?.cancel()
                            hideTooltipTask = makeHideTask { selectedBucket = nil }
                        }
                    }
            }
        }
        .frame(height: 130)
        .overlay(alignment: .topLeading) {
            if let sel = selectedBucket {
                GeometryReader { geo in
                    let halfW: CGFloat = 50
                    let clampedX = max(halfW, min(tooltipBarX, geo.size.width - halfW))
                    StatTooltip(label: sel.label, allow: sel.allow, autoAllow: sel.autoAllow, deny: sel.deny)
                        .fixedSize()
                        .allowsHitTesting(false)
                        .position(x: clampedX, y: 26)
                }
            }
        }
    }

    // MARK: - Project Card

    private var projectCard: some View {
        let maxCount = projects.first?.count ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            Text("Projects")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            VStack(spacing: 0) {
                ForEach(Array(projects.enumerated()), id: \.element.id) { i, proj in
                    projectRow(proj, maxCount: maxCount)
                    if i < projects.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func projectRow(_ proj: ProjectStat, maxCount: Int) -> some View {
        HStack(spacing: 10) {
            Text(proj.name)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 128, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.07))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.4)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: max(8, geo.size.width * CGFloat(proj.count) / CGFloat(maxCount)))
                }
            }
            .frame(height: 7)
            Text("\(proj.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Comparison Card

    private func comparisonCard(_ comp: PeriodComparison) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comparison")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
            CompMiniChartView(stat: comp.stat, current: comp.currentLabel, previous: comp.previousLabel)
        }
    }

    // MARK: - Data

    private func reload() {
        reloadTask?.cancel()
        let p = period
        let cStart = customStart
        let cEnd   = customEnd
        reloadTask = Task { @MainActor in
            // For custom: fetch prior period too so comparison works
            let fetchStart: Date
            if p == .custom {
                let duration = max(cEnd.timeIntervalSince(cStart), 86400)
                fetchStart = cStart.addingTimeInterval(-duration)
            } else {
                fetchStart = p.rangeStart
            }
            let items = await ActivityStore.shared.fetchSince(fetchStart)
            guard !Task.isCancelled else { return }

            buckets = p == .custom
                ? ActivityStats.buckets(items: items, from: cStart, to: cEnd)
                : ActivityStats.buckets(items: items, period: p)

            // Projects と Comparison は「現在の期間」だけに絞る
            let currentStart: Date = {
                let cal = Calendar.current
                let now = Date()
                switch p {
                case .day:    return cal.startOfDay(for: now)
                case .week:   return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
                case .month:  return cal.date(from: cal.dateComponents([.year, .month], from: now))!
                case .custom: return cStart
                }
            }()
            let currentEnd = p == .custom ? cEnd : Date()
            let currentItems = items.filter { $0.timestamp >= currentStart && $0.timestamp <= currentEnd }

            projects   = ActivityStats.projectBreakdown(items: currentItems)
            comparison = ActivityStats.comparisonStats(items: items, period: p,
                                                       customStart: cStart, customEnd: cEnd)
        }
    }
}

// MARK: - CompMiniChartView

private struct CompMiniChartView: View {
    let stat: ComparisonStat
    let current: String
    let previous: String

    @State private var hoveredLabel: String? = nil
    @State private var tooltipX: CGFloat = 0
    @State private var hideTooltipTask: Task<Void, Never>?

    private struct Bar: Identifiable {
        let id = UUID()
        let label: String
        let isAllow: Bool
        let count: Int
    }

    private var bars: [Bar] {
        [
            Bar(label: current,  isAllow: true,  count: stat.currentAllow),
            Bar(label: current,  isAllow: false, count: stat.currentDeny),
            Bar(label: previous, isAllow: true,  count: stat.previousAllow),
            Bar(label: previous, isAllow: false, count: stat.previousDeny),
        ]
    }

    private var deltaInfo: (label: String, color: Color) {
        let pct = stat.deltaPercent
        if stat.previousTotal == 0 && stat.currentTotal == 0 {
            return ("—", .secondary)
        } else if stat.previousTotal == 0 {
            return ("New", .green)
        } else {
            let label = (pct >= 0 ? "+" : "") + "\(Int(pct.rounded()))%"
            let color: Color = pct > 0 ? .green : pct < 0 ? .red : .secondary
            return (label, color)
        }
    }

    var body: some View {
        let delta = deltaInfo
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(current)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(delta.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(delta.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(delta.color.opacity(0.12), in: Capsule())
            }
            Chart(bars) { bar in
                BarMark(
                    x: .value("Period", bar.label),
                    y: .value("Count",  bar.count)
                )
                .foregroundStyle(bar.isAllow
                    ? AnyShapeStyle(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(LinearGradient(colors: [.red, .red.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(Color.secondary)
                }
            }
            .chartLegend(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    ZStack {
                        if let frame = proxy.plotFrame {
                            let plotRect = geo[frame]
                            if stat.currentTotal == 0 {
                                Text("No data")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .position(x: plotRect.minX + plotRect.width * 0.25, y: plotRect.midY)
                            }
                            if stat.previousTotal == 0 {
                                Text("No data")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .position(x: plotRect.minX + plotRect.width * 0.75, y: plotRect.midY)
                            }
                        }
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onContinuousHover { phase in
                                guard let frame = proxy.plotFrame else { return }
                                let plotRect = geo[frame]
                                switch phase {
                                case .active(let loc):
                                    hideTooltipTask?.cancel()
                                    hideTooltipTask = nil
                                    let midX = plotRect.minX + plotRect.width * 0.5
                                    hoveredLabel = loc.x < midX ? current : previous
                                    tooltipX = loc.x
                                case .ended:
                                    hideTooltipTask?.cancel()
                                    hideTooltipTask = makeHideTask { hoveredLabel = nil }
                                }
                            }
                    }
                }
            }
            .frame(height: 80)
            .overlay(alignment: .topLeading) {
                if let label = hoveredLabel {
                    let allow = label == current ? stat.currentAllow : stat.previousAllow
                    let deny  = label == current ? stat.currentDeny  : stat.previousDeny
                    GeometryReader { geo in
                        let halfW: CGFloat = 44
                        let clampedX = max(halfW, min(tooltipX, geo.size.width - halfW))
                        StatTooltip(label: label, allow: allow, autoAllow: 0, deny: deny)
                            .fixedSize()
                            .allowsHitTesting(false)
                            .position(x: clampedX, y: 20)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .onDisappear { hideTooltipTask?.cancel() }
    }
}

// MARK: - KPICardView

private struct KPICardView: View {
    let icon: String
    let label: String
    let value: Int
    let accent: Color
    var compact: Bool = false

    private var tint: Color { accent == .primary ? .secondary : accent }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 7) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.4)
            Text("\(value)")
                .font(.system(size: compact ? 17 : 22, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, compact ? 14 : 10)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: icon)
                .font(.system(size: compact ? 26 : 34, weight: .regular))
                .foregroundStyle(tint.opacity(0.15))
                .offset(x: 4, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - CustomRangePickerView

private struct CustomRangePickerView: View {
    @Binding var start: Date
    @Binding var end: Date
    let onApply: () -> Void

    @State private var pendingStart: Date
    @State private var pendingEnd: Date

    init(start: Binding<Date>, end: Binding<Date>, onApply: @escaping () -> Void) {
        self._start = start
        self._end = end
        self.onApply = onApply
        self._pendingStart = State(initialValue: start.wrappedValue)
        self._pendingEnd   = State(initialValue: end.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Date Range")
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 10) {
                HStack {
                    Text("From")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                    DatePicker("", selection: $pendingStart, in: ...pendingEnd, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                HStack {
                    Text("To")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                    DatePicker("", selection: $pendingEnd, in: pendingStart..., displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
            }

            HStack {
                Spacer()
                Button("Apply") {
                    start = pendingStart
                    end   = pendingEnd
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return)
            }
        }
        .padding(16)
        .frame(width: 240)
    }
}

// MARK: - Shared helpers

private func makeHideTask(after ns: UInt64 = 150_000_000, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
    Task { @MainActor in
        do { try await Task.sleep(nanoseconds: ns) } catch { return }
        action()
    }
}

private struct StatTooltip: View {
    let label: String
    let allow: Int
    let autoAllow: Int
    let deny: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                    Text("\(allow)")
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                }
                if autoAllow > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(Color.teal).frame(width: 5, height: 5)
                        Text("\(autoAllow) auto")
                            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.teal)
                    }
                }
                if deny > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(.red).frame(width: 5, height: 5)
                        Text("\(deny)")
                            .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}
