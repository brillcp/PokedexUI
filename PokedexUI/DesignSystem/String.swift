import Foundation

extension String {
    var pretty: String {
        self
            .replacingOccurrences(of: "-", with: " ")
            .folding(options: .diacriticInsensitive, locale: .current)
            .firstUppercased
    }

    func matches(query: String) -> Bool {
        let normalizedSelf = normalize
        let normalizedQuery = query.normalize
        return normalizedSelf.range(of: normalizedQuery, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

extension StringProtocol {
    var firstUppercased: String { prefix(1).uppercased() + dropFirst() }

    var normalize: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
          .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
