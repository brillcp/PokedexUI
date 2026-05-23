/// Top-level TabView selection for the root pokedex screen.
enum Tabs: Int {
    case pokedex, items, favourites, versus, search
}

extension Tabs {
    var title: String {
        switch self {
            case .pokedex: "Pokedex"
            case .items: "Items"
            case .favourites: "Favourites"
            case .versus: "Versus"
            case .search: "Search"
        }
    }

    var icon: String {
        switch self {
            case .pokedex: GridLayout.three.icon
            case .items: "xmark.triangle.circle.square.fill"
            case .favourites: "heart.fill"
            case .versus: "person.2.wave.2.fill"
            case .search: "magnifyingglass"
        }
    }
}
