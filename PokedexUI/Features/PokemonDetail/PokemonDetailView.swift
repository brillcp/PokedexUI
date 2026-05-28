import SwiftUI
import SwiftData

/// Pokemon detail screen with stats, evolution, weaknesses, and battle entry.
struct PokemonDetailView<ViewModel: PokemonDetailViewModelProtocol & Sendable>: View {
    @Environment(\.container) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: ViewModel
    @State private var showOpponentPicker = false
    @State private var battleLaunch: BattleLaunch?
    @State private var evolutionTarget: Pokemon?
    @State private var selectedType: String?
    @State private var spriteBlur: CGFloat = 0

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16.0) {
                Spacer().frame(height: 320)
                loadedContent(pokemon: viewModel.pokemon)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, offset in
            spriteBlur = min(12, max(0, (offset - 160) / 12))
        }
        .background {
            VStack {
                spriteImage()
                    .blur(radius: spriteBlur)
                Spacer()
            }
        }
        .scrollIndicators(.hidden)
        .task(id: viewModel.pokemon.id) {
            await viewModel.loadSpritesAndColor()
        }
        .task(id: viewModel.pokemon.evolutionChainId) {
            await viewModel.loadEvolutionChain(context: modelContext)
        }
        .sheet(isPresented: $showOpponentPicker) {
            OpponentPickerView(
                player: viewModel.pokemon.pokemon,
                playerTypes: viewModel.pokemon.typeNames
            ) { launch in
                showOpponentPicker = false
                battleLaunch = launch
            }
        }
        .navigationDestination(item: $battleLaunch) { launch in
            BattleView(viewModel: launch.viewModel)
        }
        .navigationDestination(item: $selectedType) { typeName in
            TypePokemonListView(typeName: typeName)
        }
        .navigationDestination(item: $evolutionTarget) { target in
            PokemonDetailView<PokemonDetailViewModel>(
                viewModel: PokemonDetailViewModel(
                    summary: target,
                    container: container
                )
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.toggleBookmark(in: modelContext)
                } label: {
                    Image(systemName: viewModel.isBookmarked ? "heart.fill" : "heart")
                        .foregroundStyle(textColor)
                }
            }
        }
        .applyPokedexStyling(
            title: "\(viewModel.pokemon.name) #\(viewModel.pokemon.id)",
            navColor: .clear,
            titleColor: textColor,
            background: viewModel.color
        )
    }
}

// MARK: - Private
private extension PokemonDetailView {
    var textColor: Color {
        viewModel.color?.isLight ?? false ? Color.darkGrey : .white
    }

    var tintColor: Color? {
        viewModel.color?.opacity(0.3)
    }

    var divider: some View {
        Divider()
            .frame(minHeight: 1.5)
            .overlay(.secondary)
    }

    func loadedContent(pokemon: PokemonViewModel) -> some View {
        VStack(spacing: 32) {
            actionButtons(pokemon: pokemon)
            SpeciesHeader(pokemon: pokemon, textColor: textColor)

            if let flavorText = pokemon.flavorText {
                DetailSection(tint: tintColor) {
                    Text(flavorText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            DetailSection(title: "Data", tint: tintColor) {
                TypesRow(typeNames: pokemon.typeNames) { selectedType = $0 }
                DetailRow(title: "Height", subtitle: pokemon.height)
                DetailRow(title: "Weight", subtitle: pokemon.weight)

                if let habitat = pokemon.habitat {
                    DetailRow(title: "Habitat", subtitle: habitat)
                }
                DetailRow(title: "Capture", subtitle: capturePercentText(for: pokemon))
                if pokemon.genderRate > 0 {
                    GenderRow(rate: pokemon.genderRate, textColor: textColor)
                }
            }

            DetailSection(title: "Type chart") {
                WeaknessGridView(
                    pokemon: pokemon,
                    textColor: textColor,
                    onSelectType: { selectedType = $0 }
                )
            }
            DetailSection(title: "Moves / Abilities") {
                DetailRow(subtitle: pokemon.moves, axis: .vertical)
                DetailRow(subtitle: pokemon.abilities, axis: .vertical)
            }
            DetailSection(title: "Stats", tint: tintColor) {
                ForEach(pokemon.stats) { stat in
                    DetailRowStat(
                        title: stat.stat.name,
                        value: stat.baseStat,
                        textColor: textColor
                    )
                }
                HStack {
                    Text("Total")
                    Spacer()
                    Text("\(pokemon.baseStatTotal)")
                }
            }

            if viewModel.evolutionStages.count > 1 {
                DetailSection(title: "Evolution", tint: tintColor) {
                    EvolutionChainView(
                        stages: viewModel.evolutionStages,
                        textColor: textColor,
                        onSelect: navigateToEvolution
                    )
                }
            }
        }
        .padding(.bottom, 32.0)
        .foregroundStyle(textColor)
        .lineHeight(.loose)
        .font(.pixel14)
    }

    func navigateToEvolution(speciesId: Int) {
        guard speciesId != viewModel.pokemon.id else { return }
        let descriptor = FetchDescriptor<Pokemon>(predicate: #Predicate { $0.id == speciesId })
        if let summary = try? modelContext.fetch(descriptor).first {
            evolutionTarget = summary
        }
    }

    func capturePercentText(for pokemon: PokemonViewModel) -> String {
        let pct = Int(round(Double(pokemon.captureRate) / 255.0 * 100.0))
        return "\(pct)%"
    }

    func spriteImage() -> some View {
        viewModel.sprite?
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 320)
    }
}

// MARK: - Private
private extension PokemonDetailView {
    func actionButtons(pokemon: PokemonViewModel) -> some View {
        HStack {
            if pokemon.latestCry != nil {
                DetailButton(icon: "speaker.wave.3.fill") {
                    Task { await viewModel.playCry() }
                }
            }
            Spacer()
            SecondaryCapsuleButton(icon: "bolt.fill", title: "Battle", color: textColor) {
                showOpponentPicker = true
            }
        }
        .tint(textColor)
        .padding(.horizontal, 24)
    }
}


#Preview {
    let vm = PokemonDetailViewModel(summary: .pikachu, container: .live)
    PokemonDetailView(viewModel: vm)
        .colorScheme(.dark)
}
