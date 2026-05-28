import OSLog
import Foundation

// ClLog — per-component logger backed by os.Logger + /tmp/gavel.log
//
// Usage:
//   private let log = ClLog("voice")
//   log.debug("transcribe start")
//   log.info("allow decided")
//   log.error("whisper binary not found")
//
// Stream in Terminal:
//   log stream --predicate 'subsystem == "com.maolab.Gavel"' --level debug
//
// Filter by category:
//   log stream --predicate 'subsystem == "com.maolab.Gavel" AND category == "voice"' --level debug
//
// Tail file:
//   tail -f /tmp/gavel.log

struct ClLog {
    let category: String
    private let oslog: Logger

    init(_ category: String) {
        self.category = category
        self.oslog = Logger(subsystem: "com.maolab.Gavel", category: category)
    }

    func debug(_ msg: @autoclosure () -> String) { emit(msg(), level: "D") }
    func info(_ msg: @autoclosure () -> String)  { emit(msg(), level: "I") }
    func error(_ msg: @autoclosure () -> String) { emit(msg(), level: "E") }

    private func emit(_ msg: String, level: String) {
        switch level {
        case "E": oslog.error("\(msg, privacy: .public)")
        case "I": oslog.info("\(msg, privacy: .public)")
        default:  oslog.debug("\(msg, privacy: .public)")
        }
        ClLog.appendToFile("[\(level)/\(category)] \(msg)")
        let lv: LogEntry.Level = level == "E" ? .error : level == "I" ? .info : .debug
        let cat = category
        Task { @MainActor in LogStore.shared.append(level: lv, category: cat, message: msg) }
    }

    // MARK: - File sink

    private static let logURL = URL(fileURLWithPath: "/tmp/gavel.log")
    private static let queue = DispatchQueue(label: "com.maolab.Gavel.log", qos: .utility)
    nonisolated(unsafe) private static var fileHandle: FileHandle? = {
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        return try? FileHandle(forWritingTo: logURL)
    }()

    private static func appendToFile(_ msg: String) {
        let ts = logTimestamp()
        let line = "\(ts) \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async {
            if let fh = Self.fileHandle {
                fh.seekToEndOfFile()
                fh.write(data)
            }
        }
    }

    private static func logTimestamp() -> String {
        var tv = timeval()
        gettimeofday(&tv, nil)
        var tm = tm()
        localtime_r(&tv.tv_sec, &tm)
        let ms = tv.tv_usec / 1000
        return String(format: "%02d:%02d:%02d.%03d", tm.tm_hour, tm.tm_min, tm.tm_sec, ms)
    }
}

// MARK: - Shared instances (one per subsystem)

extension ClLog {
    static let voice     = ClLog("voice")
    static let approval  = ClLog("approval")
    static let server    = ClLog("server")
    static let session   = ClLog("session")
    static let autoAllow = ClLog("autoAllow")
    static let app       = ClLog("app")
}
