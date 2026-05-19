import Foundation

@MainActor
final class SessionScanner {
    static let shared = SessionScanner()
    private var timer: Timer?
    private init() {}

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
        let sessions = await Task.detached(priority: .background) { scan() }.value
        AppState.shared.scannedSessions = sessions
    }

    nonisolated private static func scan() -> [SessionInfo] {
        guard let pidData = shell("/usr/bin/pgrep", args: ["-x", "claude"]),
              let pidStr = String(data: pidData, encoding: .utf8) else { return [] }

        return pidStr.components(separatedBy: .newlines)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            .compactMap { pid -> SessionInfo? in
                guard let cwd = cwdViaLsof(pid) else { return nil }
                return SessionInfo(id: "pid-\(pid)", workingDirectory: cwd)
            }
    }

    nonisolated private static func cwdViaLsof(_ pid: Int32) -> String? {
        guard let data = shell("/usr/sbin/lsof", args: ["-p", "\(pid)", "-a", "-d", "cwd", "-Fn"]),
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str.components(separatedBy: .newlines)
            .first { $0.hasPrefix("n") }
            .map { String($0.dropFirst()) }
    }

    @discardableResult
    nonisolated private static func shell(_ path: String, args: [String]) -> Data? {
        let p = Process()
        p.launchPath = path
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return data
        } catch { return nil }
    }
}
