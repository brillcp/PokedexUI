import Foundation

/// Sort options for the pokedex toolbar menu.
enum SortType: Hashable {
    case number, name
    case height, weight
    case stat(Stats)

    static let allCases: [Self] = [
        .number, .name, .height, .weight,
        .stat(.hp), .stat(.attack), .stat(.defense), .stat(.speed)
    ]
}

/// Base stat subset available as sort keys.
enum Stats: String, CaseIterable {
    case hp, attack, defense, speed

    var displayName: String { rawValue.capitalized }
}

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

extension SortType {
    var comparator: (Pokemon, Pokemon) -> Bool {
        switch self {
        case .number:
            return { (a: Pokemon, b: Pokemon) in a.id < b.id }
        case .name:
            return { (a: Pokemon, b: Pokemon) in a.name < b.name }
        case .height:
            return { (a: Pokemon, b: Pokemon) in a.height > b.height }
        case .weight:
            return { (a: Pokemon, b: Pokemon) in a.weight > b.weight }
        case .stat(let stat):
            let name = stat.rawValue
            return { (a: Pokemon, b: Pokemon) in
                let l = a.stats.first { $0.stat.name == name }?.baseStat ?? 0
                let r = b.stats.first { $0.stat.name == name }?.baseStat ?? 0
                return l > r
            }
        }
    }
}
