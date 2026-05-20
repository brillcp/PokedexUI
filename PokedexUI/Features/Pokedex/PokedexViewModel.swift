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

/// Live implementation of `PokedexViewModelProtocol`.
@Observable
final class PokedexViewModel {
    private static let totalDownloadUnits: Int = 1024 + 1024 + 540 + 1

    private let fetcher: PokemonFetcher

    var pokemonData: [Pokemon] = []
    var isLoading: Bool = false
    var loadingProgress: Double = 0
    var selectedTab: Tabs = .pokedex
    var grid: GridLayout = .three

    private var downloadTicks: Int = 0

    init(modelContext: ModelContext, container: AppContainer) {
        self.fetcher = PokemonFetcher(modelContext: modelContext, container: container)
    }
}

extension PokedexViewModel: PokedexViewModelProtocol {
    func requestPokemon() async {
        guard !isLoading else { return }

        if let cached = try? await fetcher.fetchStoredData(), !cached.isEmpty {
            pokemonData = cached
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
            pokemonData = bootstrap.pokemon
            try await fetcher.persist(bootstrap)
        } catch {
            print("PokedexViewModel: fetch failed: \(error)")
        }
    }

    func sort(by type: SortType) async {
        let sorted: [Pokemon] = await Task(priority: .userInitiated) { [weak self] in
            guard let self else { return [] }
            return self.pokemonData.sorted(by: type.comparator)
        }.value
        withAnimation(.snappy(duration: 0.25)) { pokemonData = sorted }
    }
}

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
