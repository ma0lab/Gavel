import Foundation
import os

@MainActor
final class SessionScanner {
    static let shared = SessionScanner()
    private var timer: Timer?
    private init() {}

    // path → (mtime, cwd): avoids re-reading transcripts whose content hasn't changed
    nonisolated private static let cwdCache = OSAllocatedUnfairLock(initialState: [String: (Date, String)]())

    func start() {
        Task { await Self.runScan() }
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { await Self.runScan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private static func runScan() async {
        let sessions = await Task.detached(priority: .utility) { scan() }.value
        if AppState.shared.scannedSessions != sessions {
            AppState.shared.scannedSessions = sessions
        }
    }

    nonisolated private static func scan() -> [SessionInfo] {
        var sessions = processBasedScan()
        let processedCwds = Set(sessions.compactMap { $0.workingDirectory })

        for session in transcriptBasedScan() {
            if let cwd = session.workingDirectory, !processedCwds.contains(cwd) {
                sessions.append(session)
            }
        }

        return sessions
    }

    // MARK: - Process scan

    nonisolated private static func processBasedScan() -> [SessionInfo] {
        claudePids().compactMap { pid -> SessionInfo? in
            guard let cwd = cwdViaProc(pid) else { return nil }
            return SessionInfo(id: "pid-\(pid)", workingDirectory: cwd)
        }
    }

    // MARK: - Transcript scan
    // Supplements process scan with sessions from ~/.claude/projects/ transcripts
    // modified within the last 30 minutes — catches sessions running before ClaudeBar started.

    nonisolated private static func transcriptBasedScan() -> [SessionInfo] {
        let fm = FileManager.default
        let projectsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard let dirs = try? fm.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-1800)
        var sessions = [SessionInfo]()
        var livePaths = Set<String>()

        for dir in dirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }

            // Skip dirs not touched within the cutoff window before statting their contents
            if let dirMtime = try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
               dirMtime <= cutoff { continue }

            guard let files = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            let recentJSONL = files
                .filter { $0.pathExtension == "jsonl" }
                .compactMap { url -> (URL, Date)? in
                    guard let date = (try? url.resourceValues(
                        forKeys: [.contentModificationDateKey]
                    ).contentModificationDate) else { return nil }
                    return (url, date)
                }
                .filter { $0.1 > cutoff }
                .max(by: { $0.1 < $1.1 })

            guard let (jsonlURL, mtime) = recentJSONL,
                  let cwd = cachedCwd(path: jsonlURL.path, mtime: mtime) else { continue }

            livePaths.insert(jsonlURL.path)
            sessions.append(SessionInfo(id: "transcript-\(dir.lastPathComponent)", workingDirectory: cwd))
        }

        // Prune stale cache entries (projects no longer active)
        cwdCache.withLock { [livePaths] cache in
            cache = cache.filter { livePaths.contains($0.key) }
        }

        return sessions
    }

    nonisolated private static func cachedCwd(path: String, mtime: Date) -> String? {
        // Check cache without holding the lock during I/O
        if let (cachedMtime, cwd) = cwdCache.withLock({ $0[path] }), cachedMtime == mtime {
            return cwd
        }
        guard let cwd = readCwdFromTranscript(path) else { return nil }
        cwdCache.withLock { $0[path] = (mtime, cwd) }
        return cwd
    }

    nonisolated private static func readCwdFromTranscript(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { handle.closeFile() }
        let raw = handle.readData(ofLength: 8192)

        // readData may cut in the middle of a multi-byte UTF-8 sequence — trim up to 3 bytes
        var str: String?
        for trim in 0...3 {
            if let s = String(data: raw.dropLast(trim), encoding: .utf8) { str = s; break }
        }
        guard let str else { return nil }

        for line in str.components(separatedBy: "\n").prefix(20) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            if let cwd = json["cwd"] as? String, !cwd.isEmpty { return cwd }
        }
        return nil
    }
}
