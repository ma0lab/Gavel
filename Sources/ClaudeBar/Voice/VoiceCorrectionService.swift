import Foundation

@MainActor
final class VoiceCorrectionService: ObservableObject {
    static let shared = VoiceCorrectionService()

    struct Correction: Codable {
        var original: String
        var corrected: String
        var count: Int
    }

    @Published private(set) var corrections: [Correction] = []

    private let log = ClLog.voice
    private static let maxCount = 500
    private static let storageURL: URL = {
        VoiceInputService.whisperDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("voice_corrections.json")
    }()

    private init() { load() }

    var vocabularyPrompt: String {
        corrections
            .filter { $0.count >= 3 }
            .map { $0.original }
            .joined(separator: ", ")
    }

    func apply(_ text: String) -> String {
        let result = corrections.reduce(text) {
            $0.replacingOccurrences(of: $1.original, with: $1.corrected)
        }
        if result != text { log.debug("correction apply: '\(text)' → '\(result)'") }
        return result
    }

    func save(original: String, corrected: String) {
        let orig = original.trimmingCharacters(in: .whitespacesAndNewlines)
        let corr = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !orig.isEmpty, !corr.isEmpty, orig != corr else { return }

        if let idx = corrections.firstIndex(where: { $0.original == orig }) {
            corrections[idx].corrected = corr
            corrections[idx].count += 1
            log.info("correction update: '\(orig)' → '\(corr)' count=\(corrections[idx].count)")
        } else {
            corrections.append(Correction(original: orig, corrected: corr, count: 1))
            log.info("correction new: '\(orig)' → '\(corr)' total=\(corrections.count)")
            if corrections.count > Self.maxCount {
                corrections.removeFirst(corrections.count - Self.maxCount)
            }
        }
        persist()
    }

    func delete(original: String) {
        log.info("correction delete: '\(original)'")
        corrections.removeAll { $0.original == original }
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let saved = try? JSONDecoder().decode([Correction].self, from: data) else { return }
        corrections = saved
        log.debug("correction load: \(corrections.count) entries")
    }

    private func persist() {
        let dir = Self.storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(corrections) else { return }
        try? data.write(to: Self.storageURL)
    }
}
