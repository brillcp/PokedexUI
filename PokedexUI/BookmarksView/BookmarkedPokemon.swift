import SwiftData

@Model
final class BookmarkedPokemon: Identifiable {
    @Attribute(.unique) var id: Int

    init(id: Int) {
        self.id = id
    }
}
