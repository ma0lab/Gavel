import Foundation
import AppKit

extension String {
    var projectName: String { (self as NSString).lastPathComponent }
    var shortenedPath: String { replacingOccurrences(of: NSHomeDirectory(), with: "~") }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Optional where Wrapped == String {
    var projectName: String { self?.projectName ?? "System" }
    var shortenedPath: String { self?.shortenedPath ?? "" }
    var nilIfEmpty: String? { self?.nilIfEmpty }
}

extension NSPasteboard {
    static func copy(_ string: String) {
        general.clearContents()
        general.setString(string, forType: .string)
    }
}
