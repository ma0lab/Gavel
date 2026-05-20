import Foundation

enum TranscriptReader {
    // Reads last ~16KB of the JSONL transcript and returns the text block
    // from the LAST assistant message. If that message has no text (e.g. bare
    // tool_use only), returns nil — avoids showing stale intent from earlier turns.
    static func extractLastIntent(from path: String) async -> String? {
        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > 0 else { return nil }
        let readSize = UInt64(min(fileSize, 16_384))
        try? handle.seek(toOffset: fileSize - readSize)
        guard let data = try? handle.readToEnd(),
              let chunk = String(data: data, encoding: .utf8) else { return nil }

        var lines = chunk.components(separatedBy: "\n")
        if readSize < fileSize { lines.removeFirst() }

        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            let msg = obj["message"] as? [String: Any] ?? obj
            guard (msg["role"] as? String) == "assistant",
                  let content = msg["content"] as? [[String: Any]] else { continue }

            // Found the last assistant message — extract text only from THIS message.
            // If it has no text block (bare tool_use), return nil to avoid stale intent.
            for block in content {
                guard (block["type"] as? String) == "text",
                      let text = block["text"] as? String else { continue }
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return t }
            }
            return nil
        }
        return nil
    }
}
