import SwiftData
import Foundation

/// An actor responsible for safely reading and writing model objects conforming to `PersistentModel` using SwiftData storage.
///
/// `DataStorageReader` leverages the concurrency-safe `@ModelActor` macro to provide an isolated execution context for
/// all storage operations. This ensures thread safety and data consistency when performing inserts and fetches on the underlying data layer.
///
/// - Note: This actor is generic and can operate on any model conforming to `PersistentModel`, not just `Pokemon`.
/// - Important: All operations are performed on the actor's internal `modelContext`, providing automatic protection from data races.
@ModelActor
actor DataStorageReader {
    /// Stores an array of provided `PersistentModel` instances into the actor's SwiftData model context and persists them.
    ///
    /// This method inserts each model into the context and attempts to save the changes. It is generic and supports any type conforming to
    /// `PersistentModel`.
    ///
    /// - Parameter models: An array of models to be inserted and persisted.
    /// - Throws: An error if the insertion or save operation fails in the underlying `ModelContext`.
    func store<M: PersistentModel>(_ models: [M]) throws {
        let context = modelContext
        models.forEach { context.insert($0) }
        try context.save()
    }

    /// Fetches all stored objects of type `M` from the SwiftData store, applies a transformation closure to each, and returns the results.
    ///
    /// You can specify a sort order using a `SortDescriptor`, and pass a transformation closure to process each model prior to returning.
    ///
    /// - Parameters:
    ///   - sortBy: The `SortDescriptor` that determines the order of the fetched results.
    /// - Returns: An array of the transformed models of type `M`, sorted according to the provided descriptor.
    /// - Throws: An error if the fetch operation from the context fails.
    func fetch<M: PersistentModel>(sortBy: SortDescriptor<M>) throws -> [M] {
        let context = modelContext
        let descriptor = FetchDescriptor<M>(sortBy: [sortBy])
        let storedPokemon = try context.fetch(descriptor)
        return storedPokemon
    }
}
