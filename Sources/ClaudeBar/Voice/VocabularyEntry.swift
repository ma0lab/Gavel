import Foundation

struct VocabularyEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var word: String
    var reading: String  // 空文字は読み方なし

    var promptToken: String {
        reading.isEmpty ? word : "\(word)(\(reading))"
    }
}
