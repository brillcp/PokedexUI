import Foundation
import SwiftData

/// Loads the 18 type damage relations once per app install and exposes them as
/// a fast in-memory dictionary. Used by the battle engine to compute type
/// effectiveness and by the pokedex detail view to render the weakness grid.
@MainActor
@Observable
final class TypeChartLoader {
    /// Process-wide instance. Treated like a singleton in `@Entry` defaults.
    static let shared = TypeChartLoader()

    private let typeService: TypeServiceProtocol
    private var storage: DataStorageReader?
    private var isLoading = false

    /// Keyed by type name (lowercase). Empty until first load.
    private(set) var chart: [String: TypeDetail] = [:]

    init(typeService: TypeServiceProtocol = TypeService()) {
        self.typeService = typeService
    }

    /// Wire SwiftData storage. Call once during app startup with the shared container.
    func attach(modelContainer: ModelContainer) {
        if storage == nil {
            storage = DataStorageReader(modelContainer: modelContainer)
        }
    }

    /// Hydrate from disk if available, otherwise fetch from the API once and persist.
    func loadIfNeeded() async {
        guard !isLoading, chart.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        if let cached = try? await storage?.fetch(sortBy: SortDescriptor<TypeDetail>(\.name)),
           !cached.isEmpty {
            chart = Dictionary(uniqueKeysWithValues: cached.map { ($0.name, $0) })
            return
        }

        do {
            let types = try await typeService.requestTypes()
            chart = Dictionary(uniqueKeysWithValues: types.map { ($0.name, $0) })
            try await storage?.store(types)
        } catch {
            print("TypeChartLoader: failed to load — \(error)")
        }
    }

    /// Multiplier for an attacking type against one or two defender types.
    func multiplier(attacking: String, defenders: [String]) -> Double {
        chart[attacking]?.multiplier(against: defenders) ?? 1.0
    }
}
