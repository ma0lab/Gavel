import SwiftUI

struct LogView: View {
    @ObservedObject private var state = AppState.shared

    private var sections: [(id: String, items: [ActivityItem])] {
        var order: [String] = []
        var groups: [String: [ActivityItem]] = [:]
        for item in state.recentActivity {
            let key = item.sessionId ?? "Unknown"
            if groups[key] == nil {
                order.append(key)
                groups[key] = []
            }
            groups[key]!.append(item)
        }
        return order.map { (id: $0, items: groups[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if state.recentActivity.isEmpty {
                Text("No activity yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(sections, id: \.id) { section in
                        Section {
                            ForEach(section.items) { item in
                                LogRow(item: item)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(state.activeSessions.contains(where: { $0.id == section.id }) ? Color.green : Color.gray)
                                    .frame(width: 6, height: 6)
                                Text("Session \(section.id.prefix(16))…")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text("\(state.recentActivity.count) events · \(sections.count) sessions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { state.recentActivity.removeAll() }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 520, height: 400)
    }
}

private struct LogRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.decision == .allow ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(item.decision == .allow ? Color.green : Color.red)
                .font(.body)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.toolName)
                    .font(.callout.weight(.medium))
                if !item.preview.isEmpty {
                    Text(item.preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Text(item.timestamp, style: .time)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}
