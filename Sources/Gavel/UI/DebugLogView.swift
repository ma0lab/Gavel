import SwiftUI

struct DebugLogView: View {
    @ObservedObject private var store = LogStore.shared
    @State private var selectedCategory = "All"
    @State private var selectedLevel = "All"
    @State private var autoScroll = true
    @State private var searchText = ""

    private let categories = ["All", "voice", "approval", "server", "session", "autoAllow", "app"]
    private let levels = ["All", "D", "I", "E"]

    private var filtered: [LogEntry] {
        store.entries.filter { entry in
            (selectedCategory == "All" || entry.category == selectedCategory) &&
            (selectedLevel    == "All" || entry.level.rawValue == selectedLevel) &&
            (searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText)
                                || entry.category.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            logList
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            // Category picker
            Picker("", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 90)

            // Level picker
            Picker("", selection: $selectedLevel) {
                ForEach(levels, id: \.self) { Text(levelLabel($0)).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 65)

            // Search
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))

            Spacer()

            // Entry count
            Text("\(filtered.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            // Auto-scroll toggle
            Button {
                autoScroll.toggle()
            } label: {
                Image(systemName: autoScroll ? "arrow.down.to.line" : "arrow.down.to.line")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(autoScroll ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(autoScroll ? "Auto-scroll ON" : "Auto-scroll OFF")

            // Clear
            Button {
                store.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear log")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    // MARK: - Log list

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
            .onChange(of: filtered.count) { _, _ in
                if autoScroll, let last = filtered.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // Level badge
            Text(entry.level.rawValue)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(levelColor(entry.level), in: RoundedRectangle(cornerRadius: 3))
                .padding(.top, 1)

            // Timestamp
            Text(entry.timestamp.formatted(.dateTime.hour().minute().second()))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .fixedSize()

            // Category
            Text(entry.category)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .fixedSize()

            // Message
            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(entry.level == .error ? Color.red : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(entry.level == .error ? Color.red.opacity(0.06) : Color.clear)
    }

    // MARK: - Helpers

    private func levelColor(_ level: LogEntry.Level) -> Color {
        switch level {
        case .debug: return .secondary
        case .info:  return .blue
        case .error: return .red
        }
    }

    private func levelLabel(_ raw: String) -> String {
        switch raw {
        case "D": return "Debug"
        case "I": return "Info"
        case "E": return "Error"
        default:  return "All"
        }
    }
}
