import Foundation

extension String {
    var pretty: String {
        self
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "\n:", with: ": ")
            .replacingOccurrences(of: "   ", with: "")
            .replacingOccurrences(of: "    ", with: "")
            .capitalized
    }
}
