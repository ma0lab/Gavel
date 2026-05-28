import Foundation

enum ClaudeSettingsError: LocalizedError {
    case hookBinaryNotFound
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .hookBinaryNotFound: return "gavel-hook binary not found in app bundle"
        case .writeFailed: return "Failed to write ~/.claude/settings.json"
        }
    }
}

struct ClaudeSettingsManager {
    static let settingsPath = (NSHomeDirectory() as NSString)
        .appendingPathComponent(".claude/settings.json")

    static var hookBinaryPath: String? {
        Bundle.main.url(forResource: "gavel-hook", withExtension: nil)?.path
    }

    static func isInstalled() -> Bool {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any] else { return false }

        return ["PreToolUse", "Notification", "Stop"].compactMap { hooks[$0] as? [[String: Any]] }
            .flatMap { $0 }
            .contains { entry in
                (entry["hooks"] as? [[String: Any]])?.contains { hook in
                    (hook["command"] as? String)?.contains("gavel-hook") == true
                } == true
            }
    }

    static func install(blockApprovals: Bool = false) throws {
        guard let binaryPath = hookBinaryPath else { throw ClaudeSettingsError.hookBinaryNotFound }

        var json: [String: Any]
        if let data = FileManager.default.contents(atPath: settingsPath),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = parsed
        } else {
            json = [:]
        }

        var hooks = json["hooks"] as? [String: Any] ?? [:]
        let toolMatcher = #"tool == "Bash" || tool == "Write" || tool == "Edit" || tool == "MultiEdit" || tool == "AskFollowupQuestion""#
        let preToolCmd = blockApprovals
            ? "\(binaryPath) pre_tool_use"
            : "\(binaryPath) pre_tool_use --no-block"
        hooks["PreToolUse"] = merge(existing: hooks["PreToolUse"] as? [[String: Any]],
                                    adding: hookEntry(command: preToolCmd, matcher: toolMatcher))
        // PermissionRequest: exits 0 immediately to suppress Claude Code's own terminal dialog.
        // Actual approval is handled by the PreToolUse hook via ClaudeBar popup.
        hooks["PermissionRequest"] = merge(existing: hooks["PermissionRequest"] as? [[String: Any]],
                                           adding: hookEntry(command: "\(binaryPath) permission_request"))
        hooks["Notification"] = merge(existing: hooks["Notification"] as? [[String: Any]],
                                      adding: hookEntry(command: "\(binaryPath) notification"))
        hooks["Stop"] = merge(existing: hooks["Stop"] as? [[String: Any]],
                              adding: hookEntry(command: "\(binaryPath) stop"))
        json["hooks"] = hooks

        try atomicWrite(json)
    }

    static func uninstall() throws {
        guard let data = FileManager.default.contents(atPath: settingsPath),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = json["hooks"] as? [String: Any] else { return }

        for key in ["PreToolUse", "PermissionRequest", "Notification", "Stop"] {
            if let entries = hooks[key] as? [[String: Any]] {
                hooks[key] = entries.filter { entry in
                    (entry["hooks"] as? [[String: Any]])?.contains { hook in
                        (hook["command"] as? String)?.contains("gavel-hook") == true
                    } != true
                }
            }
        }
        json["hooks"] = hooks
        try atomicWrite(json)
    }

    private static func hookEntry(command: String, matcher: String? = nil) -> [String: Any] {
        var entry: [String: Any] = [
            "hooks": [["type": "command", "command": command]]
        ]
        if let matcher { entry["matcher"] = matcher }
        return entry
    }

    private static func merge(existing: [[String: Any]]?, adding new: [String: Any]) -> [[String: Any]] {
        // Always replace existing ClaudeBar entries so matcher stays in sync with app version
        let filtered = (existing ?? []).filter { entry in
            (entry["hooks"] as? [[String: Any]])?.contains { hook in
                (hook["command"] as? String)?.contains("gavel-hook") == true
            } != true
        }
        return filtered + [new]
    }

    private static func atomicWrite(_ json: [String: Any]) throws {
        let dir = (settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        let tmpPath = settingsPath + ".gavel.tmp"

        guard FileManager.default.createFile(atPath: tmpPath, contents: data) else {
            throw ClaudeSettingsError.writeFailed
        }

        let result = tmpPath.withCString { src in
            settingsPath.withCString { dst in
                rename(src, dst)
            }
        }
        guard result == 0 else {
            try? FileManager.default.removeItem(atPath: tmpPath)
            throw ClaudeSettingsError.writeFailed
        }
    }
}
