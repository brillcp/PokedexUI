import SwiftData

/// An actor responsible for reading and writing `Pokemon` models to SwiftData storage.
///
/// `PokemonStorageReader` uses a thread-safe `ModelContext` via `@ModelActor` to perform
/// insert and fetch operations, ensuring safe concurrency when interacting with the data layer.
@ModelActor
actor PokemonStorageReader {
    /// Stores an array of `PokemonViewModel` instances in the SwiftData model context.
    ///
    /// - Parameter models: An array of view models whose `pokemon` models will be inserted.
    /// - Throws: An error if the insertion or save operation fails.
    func store(_ models: [PokemonViewModel]) throws {
        let context = modelContext
        models.forEach { context.insert($0.pokemon) }
        try context.save()
    }

    /// Fetches all stored `Pokemon` models and maps them to `PokemonViewModel`.
    ///
    /// - Returns: An array of `PokemonViewModel` instances sorted by ID in ascending order.
    /// - Throws: An error if the fetch operation fails.
    func fetchAll() throws -> [PokemonViewModel] {
        let context = modelContext
        let descriptor = FetchDescriptor<Pokemon>(sortBy: [.init(\.id)])
        let storedPokemon = try context.fetch(descriptor)
        return storedPokemon.map { PokemonViewModel(pokemon: $0) }
    }
}
