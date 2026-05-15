import SwiftData

/// Lightweight pokedex grid row — just enough fields to render a cell
/// (id + name + a deterministic sprite URL). Full details live in
/// `Pokemon` and are fetched lazily on detail/battle tap.
///
/// Pokedex order is national-dex id ascending.
@Model
final class PokemonSummary {
    @Attribute(.unique) var id: Int
    var name: String
    var isBookmarked: Bool = false
    /// Cached dominant sprite color (6-char hex, e.g. "ffcb05"). Set after the
    /// first detail-view open per pokemon — lets the next visit render the
    /// gradient background on frame 1 instead of waiting for the image color
    /// analyzer to crunch the sprite again.
    var colorHex: String? = nil

    init(id: Int, name: String, isBookmarked: Bool = false, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.isBookmarked = isBookmarked
        self.colorHex = colorHex
    }
}

extension PokemonSummary: IdentifiablePokemon {
    /// Sprite URL is derived from the id rather than fetched, so the grid
    /// can render before any per-pokemon detail call completes.
    var frontSprite: String {
        "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(id).png"
    }

    /// Summaries don't carry a back sprite — the grid never shows one.
    var backSprite: String? { nil }
}

