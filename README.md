![icon](https://user-images.githubusercontent.com/15960525/117062071-47808e00-ad23-11eb-83df-95d8efadac58.png)

# SwiftUIPokedex

SwiftPokedex is a modern example app built with **SwiftUI** by [Viktor Gidlöf](https://viktorgidlof.com).
It integrates with the [PokeAPI](https://pokeapi.co) to fetch and display Pokémon data using a clean, reactive architecture using `async / await` and `Swift Concurrency`.

This sample app demonstrates:

- Grid-based UI with LazyVGrid and smooth scrolling
- Async image loading and dominant color extraction
- Modern network abstraction using `async/await` with the [Networking](https://github.com/brillcp/Networking) framework
- Custom transitions and matched geometry effects
- View composition with protocol-oriented VM
- Infinite scrolling and pagination

The app displays a scrollable grid of Pokémon, each with a dynamically extracted dominant color based on its sprite. It also lists in-game items with searchable navigation.

<img width="280" alt="pd1" src="https://github.com/user-attachments/assets/49340bb1-e3a6-4373-8f01-0b359ce3506b" />
<img width="280" alt="pd2" src="https://github.com/user-attachments/assets/79044b0b-516d-455f-a989-c6fd6a7eb8ac" />

# Architecture 🏛

SwiftPokedex is built using a **Model + View + ViewModel (MVVM)** architecture. It cleanly separates UI logic, presentation state, and domain models. Networking and decoding are handled by a generic API service actor.

## View 📱

The SwiftUI `PokedexView` is the root view and hosts a `TabView` with two sections: "Pokedex" and "Items". The Pokémon grid uses a `LazyVGrid` and triggers sprite loading and pagination automatically:

```swift
TabView {
    NavigationStack { pokemonGridView }
        .tabItem { Label("Pokedex", systemImage: "square.grid.3x3.fill") }

    NavigationStack { itemsListView }
        .tabItem { Label("Items", systemImage: "xmark.triangle.circle.square.fill") }
}
.task { await viewModel.requestPokemon() }
```

## View Model 🧾

The view model manages asynchronous Pokémon fetching using an injected PokemonService. It tracks the loading state and appends new Pokémon to the list:
```swift
final class PokedexViewModel: ObservableObject {
    @Published var pokemon: [PokemonViewModel] = []
    @Published var isLoading: Bool = false

    func requestPokemon() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        pokemon += try await pokemonService.requestPokemon()
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


## Model 📦

Raw models like PokemonDetails, ItemData, and Stat are decoded from the PokeAPI responses and transformed into view model-friendly formats.

## API Layer 🌐

Networking is abstracted via a generic APIService actor, which handles pagination and detail resolution in parallel:
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

# Dependencies 
SwiftUIPokedex uses the HTTP framework [Networking](https://github.com/brillcp/Networking) for all the API calls to the PokeAPI. You can read more about that [here](https://github.com/brillcp/Networking#readme). It can be installed through Swift Package Manager:
```
dependencies: [
    .package(url: "https://github.com/brillcp/Networking.git", .upToNextMajor(from: "0.9.3"))
]
```

# Requirements ❗️
- Xcode 16+
- iOS 26+
- Swift 6+

