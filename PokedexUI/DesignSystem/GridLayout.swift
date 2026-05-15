import SwiftUI

/// Column count for the pokedex grid. The user toggles between 3 and 4
/// columns from the toolbar; the rawValue doubles as the column count for
/// `LazyVGrid`. `icon` shows the current layout, `otherIcon` shows what
/// tapping the toolbar button will switch to.
enum GridLayout: Int {
    case three = 3, four
}

// MARK: - Computed properties
extension GridLayout {
    var layout: [GridItem] {
        Array(repeating: GridItem(.flexible(maximum: .infinity), spacing: 2.0), count: rawValue)
    }

    var icon: String {
        switch self {
            case .three: "square.grid.3x3.fill"
            case .four: "square.grid.4x3.fill"
        }
    }

    var otherIcon: String {
        switch self {
            case .three: "square.grid.4x3.fill"
            case .four: "square.grid.3x3.fill"
        }
    }
}

// MARK: - Mutating function
extension GridLayout {
    mutating func toggle() {
        switch self {
            case .three: self = .four
            case .four: self = .three
        }
    }
}
