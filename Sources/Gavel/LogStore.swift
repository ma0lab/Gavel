import Foundation

struct LogEntry: Identifiable {
    enum Level: String { case debug = "D", info = "I", error = "E" }
    let id = UUID()
    let timestamp: Date
    let level: Level
    let category: String
    let message: String
}

@MainActor
final class LogStore: ObservableObject {
    static let shared = LogStore()
    static let maxEntries = 5000

    @Published private(set) var entries: [LogEntry] = []

    private init() {}

    func append(level: LogEntry.Level, category: String, message: String) {
        entries.append(LogEntry(timestamp: Date(), level: level, category: category, message: message))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    func clear() { entries.removeAll() }
}
