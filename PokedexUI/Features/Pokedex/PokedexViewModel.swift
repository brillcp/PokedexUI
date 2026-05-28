import Foundation
import SwiftData
import SwiftUI

/// Observable view model behind the pokedex grid.
@MainActor
protocol PokedexViewModelProtocol {
    /// All fetched Pokemon for the grid.
    var pokemon: [Pokemon] { get }
    /// `true` while fetching is in-flight.
    var isLoading: Bool { get }
    /// 0...1 progress during first-load API fetch.
    var loadingProgress: Double { get }
    /// Currently selected tab in the parent `TabView`.
    var selectedTab: Tabs { get set }
    /// Current pokedex grid layout (3 cols vs 4 cols).
    var grid: GridLayout { get set }
    /// Active sort applied to the pokemon array.
    var sortType: SortType { get set }
    /// Ascending or descending.
    var sortDirection: SortDirection { get set }

    var openFavourites: Bool { get set }
    /// Pokemon sorted by current sort settings.
    var sortedPokemon: [Pokemon] { get }
    /// Load all Pokemon: cache first, then network if needed.
    func requestPokemon() async
}

/// Concrete implementation of `PokedexViewModelProtocol`.
@MainActor
@Observable
final class PokedexViewModel {
    private static let totalDownloadUnits: Int = 1024 + 1024 + 540 + 1

    private let fetcher: PokemonFetcher
    private var downloadTicks: Int = 0

    var pokemon: [Pokemon] = []
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var selectedTab: Tabs = .pokedex
    var grid: GridLayout = .three
    var sortType: SortType = .number
    var sortDirection: SortDirection = .ascending
    var openFavourites: Bool = false

    init(modelContext: ModelContext, container: AppContainer) {
        self.fetcher = PokemonFetcher(modelContext: modelContext, container: container)
    }
}

// MARK: - PokedexViewModelProtocol

extension PokedexViewModel: PokedexViewModelProtocol {
    var sortedPokemon: [Pokemon] {
        pokemon.sorted(by: sortType.comparator(direction: sortDirection))
    }

    func requestPokemon() async {
        guard !isLoading else { return }

        if let cached = try? await fetcher.fetchStoredData(), !cached.isEmpty {
            pokemon = cached
            return
        }

        isLoading = true
        defer { isLoading = false }
        resetProgress()
        let tick: @Sendable () async -> Void = { [weak self] in
            await MainActor.run { self?.tickDownload() }
        }

        do {
            let bootstrap = try await fetcher.fetchBootstrap(onTick: tick)
            loadingProgress = 1.0
            pokemon = bootstrap.pokemon
            try await fetcher.persist(bootstrap)
        } catch {
            #if DEBUG
            print("PokedexViewModel: fetch failed: \(error)")
            #endif
        }
    }
}

// MARK: - Private
private extension PokedexViewModel {
    func resetProgress() {
        downloadTicks = 0
        loadingProgress = 0
    }

    func tickDownload() {
        downloadTicks += 1
        loadingProgress = min(1.0, Double(downloadTicks) / Double(Self.totalDownloadUnits))
    }
}
