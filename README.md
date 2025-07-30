![icon](https://github.com/user-attachments/assets/5abf1763-b290-4f12-a661-986e58fbeaad)

![swift](https://img.shields.io/badge/Swift-5.0%2B-green)
![release](https://img.shields.io/github/v/release/brillcp/pokedexui)
![platforms](https://img.shields.io/badge/Platforms-iOS%20iPadOS%20macOS-blue)
[![spm](https://img.shields.io/badge/Swift%20Package%20Manager-compatible-green)](#swift-package-manager)
[![license](https://img.shields.io/github/license/brillcp/pokedexui)](/LICENSE)
![stars](https://img.shields.io/github/stars/brillcp/pokedexui?style=social)

# PokedexUI

PokedexUI is a modern example app built with **SwiftUI** by [Viktor Gidlöf](https://viktorgidlof.com).
It integrates with the [PokeAPI](https://pokeapi.co) to fetch and display Pokémon data using a clean, reactive architecture using `async / await` and `Swift Concurrency`.

This sample app demonstrates:

- Grid-based UI with LazyVGrid and smooth scrolling
- Async image loading and dominant color extraction
- Modern network abstraction using `async/await` with the [Networking](https://github.com/brillcp/Networking) framework
- Custom transitions and matched geometry effects
- View composition with protocol-oriented view models
- Pokémon search and filtering
- Infinite scrolling

The app displays a scrollable grid of Pokémon, each with a dynamically extracted dominant color based on its sprite. It also lists in-game items with searchable navigation.

<img width="360" alt="pd1" src="https://github.com/user-attachments/assets/13c2362d-4519-4457-8e8f-94c0b97ad1f9" />
<img width="360" alt="pd2" src="https://github.com/user-attachments/assets/facfadbd-da67-4de8-9e7d-ac6c4207fbee" />


# Environment-Driven Data Flow 📊
Implements single source of truth pattern using SwiftUI Environment:
```swift
// Parent provides data through environment
.environment(\.pokemonData, viewModel.pokemon)

// Children consume reactively
@Environment(\.pokemonData) private var pokemonData
.task(id: pokemonData) { viewModel.pokemonSource = pokemonData }
```

Benefits:
- ✅ No data duplication - Pokemon data lives in one place
- ✅ Automatic propagation - Changes flow down to all child views
- ✅ Loose coupling - Views don't depend on specific parent implementations
- ✅ Reactive updates - UI automatically updates when data changes


# Architecture 🏛

PokedexUI is built using a **Model + View + ViewModel (MVVM)** architecture. It cleanly separates UI logic, presentation state, and domain models. Networking and decoding are handled by a generic API service actor. It uses Swifts reactivity macro `@Observable` that automatically tracks property changes and updates views when data changes.

## View 📱

The SwiftUI `PokedexView` is the root view and hosts a `TabView` with two sections: "Pokedex" and "Items". The Pokémon grid uses a `LazyVGrid` and triggers sprite loading and pagination automatically:

```swift
TabView(selection: $viewModel.selectedTab) {
    Tab(Tabs.pokedex.title, systemImage: viewModel.grid.icon, value: Tabs.pokedex) {
        pokedexTab
    }
    Tab(Tabs.items.title, systemImage: Tabs.items.icon, value: Tabs.items) {
        itemsTab
    }
    Tab(Tabs.favourites.title, systemImage: Tabs.favourites.icon, value: Tabs.favourites) {
        favouritesTab
    }
    Tab(Tabs.search.title, systemImage: Tabs.search.icon, value: Tabs.search, role: .search) {
        searchTab
    }
}
.applyPokedexConfiguration(viewModel: viewModel)
```

## View Model 🧾

The view model manages asynchronous Pokémon fetching using an injected PokemonService. It tracks the loading state and downloads all Pokémon data:
```swift
@Observable
final class PokedexViewModel {
    var pokemon: [PokemonViewModel] = []
    var isLoading: Bool = false

    func requestPokemon() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        pokemon = try await pokemonService.requestPokemon()
    }
}
```

Each `PokemonViewModel` also loads its sprite and computes the dominant color:
```swift
@MainActor
func loadSprite() async {
    image = await imageLoader.loadImage(from: url)
    color = Color(uiColor: image?.dominantColor ?? .darkGray)
}
```
# Searching 🔍
A high-performance, animated search feature that allows users to quickly find Pokemon by name or type with real-time filtering.

- Real-time Search: Instant results as you type
- Multi-term Support: Search for multiple keywords (e.g., "fire dragon")
- Type-aware: Search by Pokemon types as well as names
- Smooth Animations: Animated transitions between search results
- Diacritic Insensitive: Handles accented characters automatically

```swift
func updateFilteredPokemon() {
    let queryTerms = query
        .split(whereSeparator: { $0.isWhitespace })
        .map { String($0).normalize }
        .filter { !$0.isEmpty }

    guard !queryTerms.isEmpty else {
        filteredPokemon = []
        return
    }

    filteredPokemon = pokemonSource.filter { pokemonVM in
        let name = pokemonVM.name.normalize
        let types = pokemonVM.types.components(separatedBy: ",").map { $0.normalize }
        return queryTerms.allSatisfy { term in
            name.contains(term) || types.contains(where: { $0.contains(term) })
        }
    }
}
```

## Model 📦

Raw models like PokemonDetails, ItemData, and Stat are decoded from the PokeAPI responses and transformed into view model-friendly formats.

## API Layer 🌐

Networking is abstracted via a generic APIService actor, which handles detail resolution in parallel:
```swift
actor APIService<Config: ServiceConfiguration> {
    func requestData() async throws -> [Config.OutputModel] {
        // Uses withThrowingTaskGroup to fetch details concurrently
    }
}
```

`PokemonService` and `ItemService` are concrete implementations of the `ServiceConfiguration` protocol.

## Dominant Color Extraction 🎨

Each Pokémon card’s background is tinted with its sprite’s dominant color. This color is computed by extending UIImage with a method that samples and ranks pixel data.

# Clean Architecture and SOLID principle Assessment
PokedexUI demonstrates enterprise-level iOS architecture with Clean Architecture and SOLID principles.

- ✅ Clean separation of concerns
- ✅ High testability
- ✅ Low coupling between components
- ✅ Proper dependency management
- ✅ Scalable, maintainable structure

### Total score: 0.86 / 1.0

# Dependencies 
PokedexUI uses the HTTP framework [Networking](https://github.com/brillcp/Networking) for all the API calls to the PokeAPI. You can read more about that [here](https://github.com/brillcp/Networking#readme). It can be installed through Swift Package Manager:
```
dependencies: [
    .package(url: "https://github.com/brillcp/Networking.git", .upToNextMajor(from: "0.9.3"))
]
```

# Requirements ❗️
- Xcode 26+
- iOS 26+
- Swift 5+

