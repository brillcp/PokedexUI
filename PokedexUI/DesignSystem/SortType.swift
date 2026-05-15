import Foundation

/// Sort options exposed in the pokedex toolbar menu.
///
/// Only fields available on `PokemonSummary` (id + name) are shipped today .
/// height/weight/stat sorts need fully-hydrated `Pokemon` rows we don't load
/// up front anymore, so they're commented out of `allCases` until we re-add
/// a background hydration pass.
enum SortType: Hashable {
    case number, name
    case height, weight
    case stat(Stats)

    /// Cases shown in the menu. Restricted to what the summary list can sort on.
    static let allCases: [Self] = [.number, .name]
}

/// Subset of the six base stats available as sort keys. Kept small because
/// the pokedex grid only sorts on summary-derivable fields; the full stats
/// surface is available on the detail view.
enum Stats: String, CaseIterable {
    case hp, attack, defense, speed

    var displayName: String { rawValue.capitalized }
}

// MARK: - Display

extension SortType {
    var title: String {
        switch self {
            case .number: "Number"
            case .name: "Name"
            case .height: "Height"
            case .weight: "Weight"
            case .stat(let name): "\(name.displayName)"
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
}

// MARK: - Comparator

extension SortType {
    /// Comparator over `PokemonSummary`. Falls back to id for any sort that
    /// needs full-detail fields the summary doesn't carry.
    var summaryComparator: (PokemonSummary, PokemonSummary) -> Bool {
        switch self {
        case .number: { $0.id < $1.id }
        case .name: { $0.name < $1.name }
        case .height, .weight, .stat: { $0.id < $1.id }
        }
    }
}
