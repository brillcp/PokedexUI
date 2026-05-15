import Foundation

struct EvolutionChain: Decodable, Sendable {
    let chain: EvolutionLink
}

struct EvolutionLink: Decodable, Sendable {
    let species: SpeciesRef
    let evolvesTo: [EvolutionLink]
    let evolutionDetails: [EvolutionDetail]

    private enum CodingKeys: String, CodingKey {
        case species
        case evolvesTo = "evolves_to"
        case evolutionDetails = "evolution_details"
    }
}

struct EvolutionDetail: Decodable, Sendable {
    let minLevel: Int?
    let trigger: SpeciesRef?
    let item: SpeciesRef?
    let heldItem: SpeciesRef?
    let timeOfDay: String?
    let minHappiness: Int?

    private enum CodingKeys: String, CodingKey {
        case minLevel = "min_level"
        case trigger
        case item
        case heldItem = "held_item"
        case timeOfDay = "time_of_day"
        case minHappiness = "min_happiness"
    }
}

struct SpeciesRef: Decodable, Sendable, Hashable {
    let name: String
    let url: String?

    var id: Int? {
        guard let url, let last = URL(string: url)?
            .pathComponents.last(where: { !$0.isEmpty && $0 != "/" }),
              let n = Int(last)
        else { return nil }
        return n
    }
}

// MARK: - Flattened stage view
extension EvolutionChain {
    struct Stage: Identifiable {
        let species: SpeciesRef
        let trigger: EvolutionDetail?
        var id: String { species.name }
    }

    /// Linear flattening: picks the first branch at each fork. Sufficient for
    /// most pokemon; branched evolutions (eevee, wurmple) will only show one path.
    var stages: [Stage] {
        var out: [Stage] = [Stage(species: chain.species, trigger: nil)]
        var node = chain
        while let next = node.evolvesTo.first {
            out.append(Stage(species: next.species, trigger: next.evolutionDetails.first))
            node = next
        }
        return out
    }
}
