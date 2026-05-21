import SwiftUI

private struct LogFilter {
    var text = ""
    var toolName: String? = nil
    var project: String? = nil
    var decision: Decision? = nil
    var todayOnly = false

    var isEmpty: Bool {
        text.isEmpty && toolName == nil && project == nil && decision == nil && !todayOnly
    }
}

struct LogView: View {
    @ObservedObject private var state = AppState.shared
    @State private var filter = LogFilter()
    @State private var sortOrder = [KeyPathComparator(\ActivityItem.timestamp, order: .reverse)]
    @State private var selection: Set<UUID> = []
    @FocusState private var searchFocused: Bool

    private var filteredItems: [ActivityItem] {
        var base = state.recentActivity
        if let tool = filter.toolName    { base = base.filter { $0.toolName == tool } }
        if let proj = filter.project     { base = base.filter { $0.workingDirectory.projectName == proj } }
        if let dec  = filter.decision    { base = base.filter { $0.decision == dec } }
        if filter.todayOnly              { base = base.filter { Calendar.current.isDateInToday($0.timestamp) } }
        if !filter.text.isEmpty {
            let q = filter.text.lowercased()
            base = base.filter {
                $0.toolName.lowercased().contains(q) ||
                $0.preview.lowercased().contains(q) ||
                ($0.workingDirectory?.projectName.lowercased().contains(q) ?? false)
            }
        }
        return base.sorted(using: sortOrder)
    }

    private var uniqueTools: [String] {
        Array(Set(state.recentActivity.map { $0.toolName })).sorted()
    }

    private var uniqueProjects: [String] {
        Array(Set(state.recentActivity.map { $0.workingDirectory.projectName })).sorted()
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if state.recentActivity.isEmpty {
                emptyState
            } else if filteredItems.isEmpty {
                noResultsState
            } else {
                tableArea
            }
            Divider()
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium))
                TextField("Search… (⌘F)", text: $filter.text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($searchFocused)
                if !filter.text.isEmpty {
                    Button { filter.text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.separator, lineWidth: 0.5))

            Divider().frame(height: 18)

            // Tool
            filterMenu(
                label: filter.toolName ?? "Tool",
                active: filter.toolName != nil
            ) {
                Button("All") { filter.toolName = nil }
                Divider()
                ForEach(uniqueTools, id: \.self) { tool in
                    Button {
                        filter.toolName = filter.toolName == tool ? nil : tool
                    } label: {
                        if filter.toolName == tool {
                            Label(tool, systemImage: "checkmark")
                        } else {
                            Text(tool)
                        }
                    }
                }
            }

            // Project
            filterMenu(
                label: filter.project ?? "Project",
                active: filter.project != nil
            ) {
                Button("All") { filter.project = nil }
                Divider()
                ForEach(uniqueProjects, id: \.self) { proj in
                    Button {
                        filter.project = filter.project == proj ? nil : proj
                    } label: {
                        if filter.project == proj {
                            Label(proj, systemImage: "checkmark")
                        } else {
                            Text(proj)
                        }
                    }
                }
            }

            // Decision
            filterMenu(
                label: filter.decision.map { $0 == .allow ? "Allow" : "Deny" } ?? "Result",
                active: filter.decision != nil
            ) {
                Button("All") { filter.decision = nil }
                Divider()
                Button { filter.decision = filter.decision == .allow ? nil : .allow } label: {
                    if filter.decision == .allow { Label("Allow", systemImage: "checkmark") }
                    else { Text("Allow") }
                }
                Button { filter.decision = filter.decision == .deny ? nil : .deny } label: {
                    if filter.decision == .deny { Label("Deny", systemImage: "checkmark") }
                    else { Text("Deny") }
                }
            }

            Toggle(isOn: $filter.todayOnly) {
                Text("Today").font(.caption)
            }
            .toggleStyle(.checkbox)
            .foregroundStyle(filter.todayOnly ? .primary : .secondary)

            if !filter.isEmpty {
                Button("Clear") { filter = LogFilter() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func filterMenu<Content: View>(
        label: String,
        active: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(active ? .primary : .secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - Table

    private var tableArea: some View {
        let items = filteredItems
        return VStack(spacing: 0) {
            Table(items, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("") { item in
                    Image(systemName: item.decision == .allow ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(item.decision == .allow ? .green : .red)
                        .font(.system(size: 12))
                        .contextMenu {
                            Button("Filter: \(item.decision == .allow ? "Allow" : "Deny")") {
                                filter.decision = item.decision
                            }
                        }
                }
                .width(20)

                TableColumn("Tool", value: \.toolName) { item in
                    Text(item.toolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                        .contextMenu {
                            Button("Filter by \"\(item.toolName)\"") { filter.toolName = item.toolName }
                        }
                }
                .width(min: 55, ideal: 80, max: 110)

                TableColumn("Project") { item in
                    let proj = item.workingDirectory.projectName
                    Text(proj)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .contextMenu {
                            Button("Filter by \"\(proj)\"") { filter.project = proj }
                        }
                }
                .width(min: 60, ideal: 110, max: 150)

                TableColumn("Preview", value: \.preview) { item in
                    Text(item.preview.isEmpty ? "—" : item.preview)
                        .font(.caption)
                        .foregroundStyle(item.preview.isEmpty ? .quaternary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contextMenu {
                            if !item.preview.isEmpty {
                                Button("Copy") { NSPasteboard.copy(item.preview) }
                            }
                        }
                }

                TableColumn("Time", value: \.timestamp) { item in
                    Text(item.timestamp, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .width(52)
            }
            .tableStyle(.inset)

            if let id = selection.first, let item = items.first(where: { $0.id == id }) {
                Divider()
                DetailPanel(item: item)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text(filter.isEmpty
                 ? "\(state.recentActivity.count) events"
                 : "\(filteredItems.count) of \(state.recentActivity.count) events")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                let lines = filteredItems.map {
                    "\($0.decision == .allow ? "✓" : "✗")\t\($0.toolName)\t\($0.workingDirectory.projectName)\t\($0.preview)\t\(formatted($0.timestamp))"
                }
                NSPasteboard.copy(lines.joined(separator: "\n"))
            } label: {
                Label("Export", systemImage: "square.and.arrow.up").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Copy filtered results as TSV")

            Button("Clear log") { state.clearActivity(); filter = LogFilter(); selection = [] }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }

    // MARK: - Empty states

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No activity yet")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.quaternary)
            Text("No matching events")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f.string(from: date)
    }
}

// MARK: - Detail panel

private struct DetailPanel: View {
    let item: ActivityItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: item.decision == .allow ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(item.decision == .allow ? .green : .red)
                    .font(.system(size: 11))
                Text(item.toolName)
                    .font(.caption.weight(.semibold))
                Text("·").foregroundStyle(.quaternary)
                Text(item.workingDirectory.projectName)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(item.timestamp, format: .dateTime.month().day().hour().minute().second())
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.quaternary)
                Button {
                    NSPasteboard.copy(item.preview)
                } label: {
                    Image(systemName: "doc.on.doc").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help("Copy")
            }
            if !item.preview.isEmpty {
                Text(item.preview)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3))
    }
}
