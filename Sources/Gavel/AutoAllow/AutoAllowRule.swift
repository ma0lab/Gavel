import Foundation

struct AutoAllowRule: Codable, Identifiable, Sendable {
    var id: UUID
    var toolName: String
    var isEnabled: Bool
    var commandPattern: String?

    init(id: UUID = UUID(), toolName: String, isEnabled: Bool = true, commandPattern: String? = nil) {
        self.id = id
        self.toolName = toolName
        self.isEnabled = isEnabled
        self.commandPattern = commandPattern
    }

    static let bash = "Bash"
    static let knownTools = ["Bash", "Read", "Write", "Edit", "Glob", "Grep", "WebFetch", "WebSearch"]

    static let defaults: [AutoAllowRule] = [
        .init(toolName: "Read"),
        .init(toolName: "Grep"),
        .init(toolName: "Glob"),
        .init(toolName: bash, commandPattern: #"^(grep|rg|find|ls|cat|head|tail|wc|diff|stat|echo|pwd|which)"#),
    ]

    static func migrated(_ rules: [AutoAllowRule]) -> [AutoAllowRule] {
        rules.compactMap { rule in
            guard !knownTools.contains(rule.toolName) else { return rule }
            guard let pattern = rule.commandPattern, !pattern.isEmpty else { return nil }
            return AutoAllowRule(id: rule.id, toolName: bash, isEnabled: rule.isEnabled, commandPattern: pattern)
        }
    }
}

func isEnvFilePath(_ path: String) -> Bool {
    let name = (path.lowercased() as NSString).lastPathComponent
    return name == ".env" || name.hasPrefix(".env.") || name.hasSuffix(".env")
}
