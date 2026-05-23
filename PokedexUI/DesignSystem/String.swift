import Foundation

extension String {
    var pretty: String {
        self
            .replacingOccurrences(of: "-", with: " ")
            .folding(options: .diacriticInsensitive, locale: .current)
            .firstUppercased
    }
}

extension StringProtocol {
    var firstUppercased: String { prefix(1).uppercased() + dropFirst() }

    var normalize: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
          .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
