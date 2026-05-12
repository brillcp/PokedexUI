import Foundation

extension String {
    var pretty: String {
        self
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "é", with: "e")
            .replacingOccurrences(of: "à", with: "a")
            .capitalized
    }
}

extension StringProtocol {
    var normalize: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
          .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
