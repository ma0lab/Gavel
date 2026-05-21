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
    @State private var selectedSection: LogSection?

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
        if let section = selectedSection {
            SessionDetail(section: section) { selectedSection = nil }
        } else {
            sessionList
        }
    }

    // MARK: - Session list

    private var sessionList: some View {
        VStack(spacing: 0) {
            if state.recentActivity.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sections) { section in
                        Button { selectedSection = section } label: {
                            SessionRow(section: section)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.inset)

                Divider()
                HStack {
                    Text("\(state.recentActivity.count) events · \(sections.count) sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") { state.clearActivity() }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.bar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
}

// MARK: - Shared subviews

private struct ActiveBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(Color.green).frame(width: 5, height: 5)
            Text("active").font(.caption2.weight(.medium)).foregroundStyle(.green)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.green.opacity(0.10), in: Capsule())
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let section: LogSection

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill((section.isActive ? Color.green : Color.secondary).opacity(0.12))
                    .frame(width: 32, height: 32)
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(section.isActive ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(section.projectName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if section.isActive { ActiveBadge() }
                }
                if !section.shortPath.isEmpty {
                    Text(section.shortPath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Text("\(section.items.count)")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Session detail

private struct SessionDetail: View {
    let section: LogSection
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.subheadline.weight(.semibold))
                        Text("Sessions")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(section.projectName)
                            .font(.subheadline.weight(.semibold))
                        if section.isActive { ActiveBadge() }
                    }
                    if !section.shortPath.isEmpty {
                        Text(section.shortPath)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text("\(section.items.count) events")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(section.items) { item in
                        LogRow(item: item)
                        if item.id != section.items.last?.id {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Log row

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
                        .background(toolColor(item.toolName).opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 4))
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
        case "Idle":         return .indigo
        default:             return .secondary
        }
    }
}
