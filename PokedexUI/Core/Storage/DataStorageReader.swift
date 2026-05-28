import SwiftData
import Foundation

/// Actor for safely reading and writing `PersistentModel` objects via SwiftData.
/// Generic across any model type. All operations run on the actor's internal context.
@ModelActor
actor DataStorageReader {
    func store<M: PersistentModel>(_ models: [M]) throws {
        let context = modelContext
        models.forEach { context.insert($0) }
        try context.save()
    }

    func fetch<M: PersistentModel>(sortBy: SortDescriptor<M>) throws -> [M] {
        let context = modelContext
        let descriptor = FetchDescriptor<M>(sortBy: [sortBy])
        return try context.fetch(descriptor)
    }

    func fetch<M: PersistentModel>(predicate: Predicate<M>) throws -> [M] {
        let context = modelContext
        let descriptor = FetchDescriptor<M>(predicate: predicate)
        return try context.fetch(descriptor)
    }

    func clear<M: PersistentModel>(_ type: M.Type) {
        let context = modelContext
        do {
            try context.delete(model: M.self)
            try context.save()
        } catch {
            #if DEBUG
            print("Skipped clear for \(M.self): \(error)")
            #endif
        }
    }

    func delete<M: PersistentModel>(matching predicate: Predicate<M>) throws {
        let context = modelContext
        try context.delete(model: M.self, where: predicate)
        try context.save()
    }
}
