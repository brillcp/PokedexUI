import SwiftUI

/// Grid of `Pokemon` rows used by the pokedex, search, and bookmarks tabs.
/// Tapping a cell pushes `PokemonDetailView`. `isLoading` only shows a
/// spinner on a cold start when the list is still empty.
struct PokedexGridView: View {
    @Namespace private var namespace
    @Environment(\.container) private var container

    let pokemon: [Pokemon]
    var grid: GridLayout = .three
    var isLoading: Bool = false
    var loadingProgress: Double = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: grid.layout, spacing: 2.0) {
                ForEach(pokemon, id: \.id) { vm in
                    PokedexGridItem(
                        pokemon: vm,
                        grid: grid,
                        namespace: namespace
                    )
                }
            }
            .padding(.vertical, 2.0)
        }
        .overlay {
            if isLoading && pokemon.isEmpty {
                IndexingOverlay(progress: loadingProgress)
            }
        }
        .navigationDestination(for: Pokemon.self) { vm in
            PokemonDetailView(
                viewModel: PokemonDetailViewModel(
                    summary: vm,
                    container: container
                )
            )
            .navigationTransition(.zoom(sourceID: vm.id, in: namespace))
        }
    }
}

// MARK: - Indexing overlay

/// Full-screen overlay shown during first-load API fetch with a
/// determinate progress bar and percentage label.
private struct IndexingOverlay: View {
    let progress: Double

    var body: some View {
        VStack(spacing: 16) {
            PixelSpinner()
                .opacity(progress >= 1.0 ? 1.0 : 0.0)
            ProgressView(value: progress)
                .tint(.pokedexRed)
                .frame(width: 200)
            Text("Indexing Pokedex \(Int(progress * 100))%")
                .font(.pixel14)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Grid item

/// Single cell in the pokedex grid. Loads the dominant sprite color for
/// the background tint and uses `SpriteImage` for the sprite itself.
/// Overlays id + name in 3-column layout.
private struct PokedexGridItem: View {
    @Environment(\.container) private var container

    @State private var color: Color?
    @State private var isLight = false

    let pokemon: Pokemon
    let grid: GridLayout
    let namespace: Namespace.ID

    var body: some View {
        NavigationLink(value: pokemon) {
            SpriteImage(url: pokemon.frontSprite) { uiImage in
                guard let resolved = await container.imageColorAnalyzer.dominantColor(for: pokemon.id, image: uiImage)
                else { return }
                isLight = resolved.isLight
                withAnimation(.easeInOut(duration: 0.2)) {
                    color = resolved
                }
            }
            .background(color)
            .overlay {
                if grid == .three {
                    CardOverlay(
                        id: pokemon.id,
                        name: pokemon.name,
                        isLight: isLight
                    )
                }
            }
            .font(.pixel12)
            .matchedTransitionSource(id: pokemon.id, in: namespace)
        }
    }
}

// MARK: - Card overlay

/// Id pill (top-right) + name (bottom-left) overlaid on the sprite.
/// Foreground color flips to black on light sprite backgrounds.
private struct CardOverlay: View {
    let id: Int
    let name: String
    let isLight: Bool

    var body: some View {
        VStack {
            HStack {
                Spacer()
                Text("#\(id)")
                    .padding(8)
            }
            Spacer()
            Text(name)
        }
        .padding(.bottom, 10)
        .foregroundStyle(isLight ? .black : .white)
    }
}
