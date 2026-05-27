import Foundation
import SQLite3

@MainActor
final class ActivityStore {
    static let shared = ActivityStore()

    private var db: OpaquePointer?
    private var dbPath: String = ""
    private static let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private init() { open() }

    private func open() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeBar")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent("activity.db").path
        dbPath = path
        guard sqlite3_open(path, &db) == SQLITE_OK else { return }
        exec("PRAGMA journal_mode=WAL")
        exec("PRAGMA synchronous=NORMAL")
        exec("""
            CREATE TABLE IF NOT EXISTS activity (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                session_id TEXT,
                tool_name TEXT NOT NULL,
                decision TEXT NOT NULL,
                preview TEXT NOT NULL DEFAULT '',
                working_directory TEXT
            )
        """)
        // Migrate: add is_auto_allowed column if not present (safe to ignore "duplicate column" error)
        exec("ALTER TABLE activity ADD COLUMN is_auto_allowed INTEGER NOT NULL DEFAULT 0")
        exec("CREATE INDEX IF NOT EXISTS idx_ts ON activity(timestamp DESC)")
        exec("CREATE INDEX IF NOT EXISTS idx_wd ON activity(working_directory)")
    }

    func insert(_ item: ActivityItem) {
        let sql = """
            INSERT OR REPLACE INTO activity
                (id, timestamp, session_id, tool_name, decision, preview, working_directory, is_auto_allowed)
            VALUES (?,?,?,?,?,?,?,?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, item.id.uuidString)
        sqlite3_bind_double(stmt, 2, item.timestamp.timeIntervalSinceReferenceDate)
        bindOptional(stmt, 3, item.sessionId)
        bindText(stmt, 4, item.toolName)
        bindText(stmt, 5, item.decision.rawValue)
        bindText(stmt, 6, item.preview)
        bindOptional(stmt, 7, item.workingDirectory)
        sqlite3_bind_int(stmt, 8, item.isAutoAllowed ? 1 : 0)
        sqlite3_step(stmt)
    }

    func fetchRecent(limit: Int = 200) -> [ActivityItem] {
        query("SELECT * FROM activity ORDER BY timestamp DESC LIMIT ?", doubles: [], texts: [], limit: limit)
    }

    func fetchToday() async -> [ActivityItem] {
        await fetchSince(Calendar.current.startOfDay(for: Date()))
    }

    func fetchSince(_ from: Date) async -> [ActivityItem] {
        let path = dbPath
        let ts = from.timeIntervalSinceReferenceDate
        return await Task.detached(priority: .utility) {
            // Open a separate read-only connection — WAL mode supports concurrent readers
            var readDb: OpaquePointer?
            guard sqlite3_open_v2(path, &readDb,
                                  SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK
            else { return [] }
            defer { sqlite3_close(readDb) }
            let sql = "SELECT * FROM activity WHERE timestamp >= ? ORDER BY timestamp DESC"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(readDb, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_double(stmt, 1, ts)
            var result: [ActivityItem] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let item = Self.decodeRow(stmt) { result.append(item) }
            }
            return result
        }.value
    }

    func clearAll() {
        exec("DELETE FROM activity")
    }

    func close() {
        sqlite3_close(db)
        db = nil
    }

    // MARK: - Private

    private func query(_ sql: String, doubles: [Double], texts: [String], limit: Int) -> [ActivityItem] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var col: Int32 = 1
        for d in doubles { sqlite3_bind_double(stmt, col, d); col += 1 }
        for t in texts   { bindText(stmt, col, t);             col += 1 }
        sqlite3_bind_int64(stmt, col, Int64(limit))
        return collectRows(stmt)
    }

    private func collectRows(_ stmt: OpaquePointer?) -> [ActivityItem] {
        var result: [ActivityItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let item = decode(stmt) { result.append(item) }
        }
        return result
    }

    private func decode(_ stmt: OpaquePointer?) -> ActivityItem? { Self.decodeRow(stmt) }

    nonisolated static func decodeRow(_ stmt: OpaquePointer?) -> ActivityItem? {
        guard let idStr = col(stmt, 0),
              let id = UUID(uuidString: idStr),
              let toolName = col(stmt, 3),
              let decisionStr = col(stmt, 4),
              let decision = Decision(rawValue: decisionStr)
        else { return nil }
        return ActivityItem(
            id: id,
            timestamp: Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 1)),
            sessionId: col(stmt, 2),
            toolName: toolName,
            decision: decision,
            preview: col(stmt, 5) ?? "",
            workingDirectory: col(stmt, 6),
            isAutoAllowed: sqlite3_column_int(stmt, 7) != 0
        )
    }

    nonisolated static func col(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard let ptr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: ptr)
    }

    private func bindText(_ stmt: OpaquePointer?, _ col: Int32, _ val: String) {
        sqlite3_bind_text(stmt, col, val, -1, Self.SQLITE_TRANSIENT)
    }

    private func bindOptional(_ stmt: OpaquePointer?, _ col: Int32, _ val: String?) {
        if let v = val { bindText(stmt, col, v) } else { sqlite3_bind_null(stmt, col) }
    }

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }
}
