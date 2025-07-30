import Foundation

enum Tabs: Int {
    case pokedex, items, favourites, search
}

// MARK: - Calculated properties
extension Tabs {
    var title: String {
        switch self {
            case .pokedex: "Pokedex"
            case .items: "Items"
            case .favourites: "Favourites"
            case .search: "Search"
        }
    }

    var icon: String {
        switch self {
            case .pokedex: GridLayout.three.icon
            case .items: "xmark.triangle.circle.square.fill"
            case .favourites: "bookmark.fill"
            case .search: "magnifyingglass"
        }
    }
}
