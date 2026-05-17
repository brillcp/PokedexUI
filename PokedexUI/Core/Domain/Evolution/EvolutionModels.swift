import Foundation
import SwiftData

/// `/evolution-chain/{id}` payload. Root of a recursive evolution tree
/// (Pichu → Pikachu → Raichu, etc.). PokedexUI flattens this into a linear
/// stage list for the detail-view evolution row.
struct EvolutionChain: Codable, Sendable {
    let chain: EvolutionLink
}

/// SwiftData-backed cache of one `/evolution-chain/{id}` response. The wire
/// payload is stored as JSON `Data` so the recursive `EvolutionChain` struct
/// stays decoupled from SwiftData's relationship model.
@Model
final class EvolutionChainEntity {
    @Attribute(.unique) var chainId: String
    var payload: Data

    init(chainId: String, payload: Data) {
        self.chainId = chainId
        self.payload = payload
    }
}

/// One node in the evolution tree. Each link points at one species and
/// carries any number of `evolvesTo` children with the trigger details
/// (level, item, friendship, etc.).
struct EvolutionLink: Codable, Sendable {
    let species: SpeciesRef
    let evolvesTo: [EvolutionLink]
    let evolutionDetails: [EvolutionDetail]

    private enum CodingKeys: String, CodingKey {
        case species
        case evolvesTo = "evolves_to"
        case evolutionDetails = "evolution_details"
    }
}

/// Trigger metadata for an evolution edge. PokeAPI exposes many fields; we
/// pull the most common ones (level, item, time of day, friendship) and let
/// the UI pick whichever is most descriptive.
struct EvolutionDetail: Codable, Sendable {
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

/// Name + URL reference to a species. `id` parses the trailing path
/// component of `url` so callers can map a stage back to a `Pokemon`.
struct SpeciesRef: Codable, Sendable, Hashable {
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
    /// Flattened evolution stage: one species plus the trigger that produced
    /// it (nil for the first stage). Used directly by `EvolutionChainView`.
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
