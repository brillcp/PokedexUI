import SwiftUI

enum GridLayout {
    case three, four
}

// MARK: -
extension GridLayout {
    var layout: [GridItem] {
        switch self {
        case .three:
            [
                GridItem(.flexible(maximum: .infinity)),
                GridItem(.flexible(maximum: .infinity)),
                GridItem(.flexible(maximum: .infinity)),
            ]
        case .four:
            GridLayout.three.layout + [GridItem(.flexible(maximum: .infinity))]
        }
    }

    var icon: String {
        switch self {
            case .three: "square.grid.3x3.fill"
            case .four: "square.grid.4x3.fill"
        }
    }

    mutating func toggle() {
        switch self {
            case .three: self = .four
            case .four: self = .three
        }
    }
}
