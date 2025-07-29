import Foundation

enum Tabs: Int {
    case pokedex, items, search
}

extension Tabs {
    var title: String {
        switch self {
            case .pokedex: "Pokedex"
            case .items: "Items"
            case .search: "Search"
        }
    }

    var icon: String {
        switch self {
            case .pokedex: GridLayout.three.icon
            case .items: "xmark.triangle.circle.square.fill"
            case .search: "magnifyingglass"
        }
    }
}
