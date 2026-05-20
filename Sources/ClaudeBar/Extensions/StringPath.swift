import Foundation

extension String {
    var projectName: String { (self as NSString).lastPathComponent }
    var shortenedPath: String { replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}

extension Optional where Wrapped == String {
    var projectName: String { self?.projectName ?? "(unknown)" }
    var shortenedPath: String { self?.shortenedPath ?? "" }
}
