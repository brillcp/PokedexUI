import Foundation

enum Stats: String, CaseIterable {
    case hp, attack, defense, speed

    var displayName: String {
        rawValue.capitalized
    }
}

enum SortType: Hashable {
    case number, name, height, weight
    case stat(Stats)

    static let allCases: [Self] = [
        .number, .name, .height, .weight
    ] + Stats.allCases.map { .stat($0) }
}

// MARK: -
extension SortType {
    var title: String {
        switch self {
            case .number: "Sort by Number"
            case .name: "Sort by Name"
            case .height: "Sort by Height"
            case .weight: "Sort by Weight"
            case .stat(let name): "Sort by \(name.displayName)"
        }
    }

    var systemImage: String {
        switch self {
        case .number: "number"
        case .name: "textformat"
        case .height: "arrow.up.and.down"
        case .weight: "scalemass.fill"
        case .stat(let stat):
            switch stat {
            case .hp: "heart.fill"
            case .attack: "bolt.fill"
            case .defense: "shield.fill"
            case .speed: "speedometer"
            }
        }
    }

    var comparator: (PokemonViewModel, PokemonViewModel) -> Bool {
        switch self {
        case .number: { $0.id < $1.id }
        case .name: { $0.name < $1.name }
        case .height: { $0.pokemon.height > $1.pokemon.height }
        case .weight: { $0.pokemon.weight > $1.pokemon.weight }
        case .stat(let stat):
            { $0.baseStat(for: stat) > $1.baseStat(for: stat) }
        }
    }
}

// MARK: - PokemonViewModel base stat extension
private extension PokemonViewModel {
    func baseStat(for stat: Stats) -> Int {
        statLookup[stat.rawValue] ?? 0
    }
}
