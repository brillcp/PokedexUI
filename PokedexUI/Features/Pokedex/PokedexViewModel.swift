import Foundation
import SwiftData
import SwiftUI

/// Observable view model behind the pokedex grid.
@MainActor
protocol PokedexViewModelProtocol {
    /// The grid's data source.
    var pokemonData: [Pokemon] { get }
    /// `true` while fetching is in-flight.
    var isLoading: Bool { get }
    /// 0...1 progress during first-load API fetch.
    var loadingProgress: Double { get }
    /// Currently selected tab in the parent `TabView`.
    var selectedTab: Tabs { get set }
    /// Current pokedex grid layout (3 cols vs 4 cols).
    var grid: GridLayout { get set }

    /// Load all Pokemon: cache first, then network if needed.
    func requestPokemon() async
    /// Re-sort the in-memory array.
    func sort(by type: SortType) async
}

// MARK: - Implementation

/// Live implementation of `PokedexViewModelProtocol`. Cache-first with
/// progress reporting on first-load API fetch.
@Observable
final class PokedexViewModel {
    private let storageReader: DataStorageReader
    private let pokemonService: PokemonServiceProtocol

    var pokemonData: [Pokemon] = []
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var selectedTab: Tabs = .pokedex
    var grid: GridLayout = .three

    init(modelContext: ModelContext, service: PokemonServiceProtocol = PokemonService()) {
        storageReader = DataStorageReader(modelContainer: modelContext.container)
        pokemonService = service
        observeHydration()
    }
}

// MARK: - PokedexViewModelProtocol

extension PokedexViewModel: PokedexViewModelProtocol {
    func requestPokemon() async {
        guard !isLoading else { return }
        isLoading = true

        if let cached = try? await storageReader.fetch(sortBy: SortDescriptor<Pokemon>(\.id)),
           !cached.isEmpty {
            pokemonData = cached
            isLoading = false
            return
        }

        do {
            let pokemon = try await pokemonService.requestAllPokemon { [weak self] loaded, total in
                await MainActor.run {
                    self?.loadingProgress = Double(loaded) / Double(total)
                }
            }
            pokemonData = pokemon
            isLoading = false

            Task(priority: .background) { [storageReader] in
                try? await storageReader.store(pokemon)
            }
        } catch {
            isLoading = false
            print("PokedexViewModel: fetch failed: \(error)")
        }
    }

    func refreshFromStorage() async {
        guard let fresh = try? await storageReader.fetch(sortBy: SortDescriptor<Pokemon>(\.id)),
              !fresh.isEmpty else { return }
        pokemonData = fresh
    }

    func sort(by type: SortType) async {
        let sorted: [Pokemon] = await Task(priority: .userInitiated) { [weak self] in
            guard let self else { return [] }
            return self.pokemonData.sorted(by: type.comparator)
        }.value
        withAnimation(.snappy(duration: 0.25)) { pokemonData = sorted }
    }
}

// MARK: - Hydration observer

private extension PokedexViewModel {
    func observeHydration() {
        NotificationCenter.default.addObserver(
            forName: .pokemonHydrationComplete,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshFromStorage()
            }
        }
    }
}
