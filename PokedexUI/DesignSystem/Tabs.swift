/// Top-level TabView selection for the root pokedex screen.
enum Tabs: Int {
    case pokedex, items, favourites, search
}

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
            case .favourites: "heart.fill"
            case .search: "magnifyingglass"
        }
    }
}
