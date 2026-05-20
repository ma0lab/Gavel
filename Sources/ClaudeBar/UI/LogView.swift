import SwiftUI

private struct LogSection: Identifiable {
    let workingDirectory: String?
    let projectName: String
    let shortPath: String
    let isActive: Bool
    let items: [ActivityItem]
    var id: String { workingDirectory ?? "__unknown__" }
}

struct LogView: View {
    @ObservedObject private var state = AppState.shared

    private var sections: [LogSection] {
        var order: [String] = []
        var groups: [String: [ActivityItem]] = [:]
        for item in state.recentActivity {
            let key = item.workingDirectory ?? "__unknown__"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(item)
        }
        let activeDirs = Set(state.activeSessions.compactMap { $0.workingDirectory })
        return order.map { key in
            let wd: String? = key == "__unknown__" ? nil : key
            return LogSection(
                workingDirectory: wd,
                projectName: wd.projectName,
                shortPath: wd.shortenedPath,
                isActive: wd.map { activeDirs.contains($0) } ?? false,
                items: groups[key] ?? []
            )
        }
    }

    var body: some View {
        let secs = sections
        return VStack(spacing: 0) {
            if state.recentActivity.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(secs) { section in
                            Section {
                                ForEach(section.items) { item in
                                    LogRow(item: item)
                                    if item.id != section.items.last?.id {
                                        Divider().padding(.leading, 56)
                                    }
                                }
                            } header: {
                                ProjectHeader(section: section)
                            }
                        }
                    }
                }
            }
            footer(sectionCount: secs.count)
        }
    }

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

    private func footer(sectionCount: Int) -> some View {
        HStack {
            Text("\(state.recentActivity.count) events · \(sectionCount) projects")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { state.clearActivity() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }
}

private struct ProjectHeader: View {
    let section: LogSection

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill((section.isActive ? Color.green : Color.secondary).opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(section.isActive ? .green : .secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(section.projectName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !section.shortPath.isEmpty {
                    Text(section.shortPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            if section.isActive {
                HStack(spacing: 4) {
                    Circle().fill(Color.green).frame(width: 5, height: 5)
                    Text("active").font(.caption2.weight(.medium)).foregroundStyle(.green)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.green.opacity(0.10), in: Capsule())
            }
            Text("\(section.items.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.quaternary)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

private struct LogRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.decision == .allow ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(item.decision == .allow ? .green : .red)
                .font(.system(size: 15))
                .frame(width: 28, height: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Text(item.toolName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(toolColor(item.toolName))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(toolColor(item.toolName).opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    Spacer()
                    Text(item.timestamp, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.quaternary)
                }
                if !item.preview.isEmpty {
                    Text(item.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func toolColor(_ name: String) -> Color {
        switch name {
        case "Bash":         return .blue
        case "Edit":         return .orange
        case "Write":        return .purple
        case "Read":         return .secondary
        case "Notification": return .teal
        default:             return .secondary
        }
    }
}
