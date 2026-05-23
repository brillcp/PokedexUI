/// Top-level TabView selection for the root pokedex screen.
enum Tabs: Int {
    case pokedex, items, favourites, battle, search
}

extension Tabs {
    var title: String {
        switch self {
            case .pokedex: "Pokedex"
            case .items: "Items"
            case .favourites: "Favourites"
            case .battle: "Battle"
            case .search: "Search"
        }
    }

    var icon: String {
        switch self {
            case .pokedex: GridLayout.three.icon
            case .items: "xmark.triangle.circle.square.fill"
            case .favourites: "heart.fill"
            case .battle: "person.2.wave.2.fill"
            case .search: "magnifyingglass"
        }
    }
}
