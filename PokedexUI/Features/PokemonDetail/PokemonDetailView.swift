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

    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16.0) {
                spriteImage()
                loadedContent(pokemon: viewModel.pokemon)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    var divider: some View {
        Divider()
            .frame(minHeight: 1.5)
            .overlay(.secondary)
    }

    func loadedContent(pokemon: PokemonViewModel) -> some View {
        VStack(spacing: 32) {
            actionButtons(pokemon: pokemon)
            speciesHeader(pokemon: pokemon)

            if let flavorText = pokemon.flavorText?.pretty {
                Text(flavorText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(textColor)
                    .background(textColor.opacity(0.1))
                    .clipShape(RoundedRectangle.card)
            }
            typesRow(pokemon: pokemon)
            DetailRow(title: "Height", subtitle: pokemon.height)
            DetailRow(title: "Weight", subtitle: pokemon.weight)

            if let habitat = pokemon.habitat {
                DetailRow(title: "Habitat", subtitle: habitat)
            }
            DetailRow(title: "Capture", subtitle: capturePercentText(for: pokemon))
            if pokemon.genderRate > 0 {
                GenderRow(rate: pokemon.genderRate, textColor: textColor)
            }
            WeaknessGridView(
                pokemon: pokemon,
                textColor: textColor
            )

            rowSection(title: "Abilities", data: pokemon.abilities)
            rowSection(title: "Moves", data: pokemon.moves)
            divider
            statsSection(pokemon: pokemon)
            divider
            EvolutionChainView(
                stages: viewModel.evolutionStages,
                textColor: textColor,
                onSelect: navigateToEvolution
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32.0)
        .foregroundStyle(textColor)
        .lineHeight(.loose)
        .font(.pixel14)
    }

    func speciesHeader(pokemon: PokemonViewModel) -> some View {
        HStack {
            if let genus = pokemon.genus {
                Text(genus.pretty)
                    .font(.pixel14)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let gen = pokemon.generationName?.uppercased().replacingOccurrences(of: "GENERATION-", with: "GEN ") {
                Chip(gen, style: .custom(background: textColor.opacity(0.1), foreground: textColor))
            }
            if pokemon.isLegendary { Chip("LEGENDARY", style: .primary) }
            if pokemon.isMythical { Chip("MYTHICAL", style: .primary) }
        }
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

    func typesRow(pokemon: PokemonViewModel) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Types")
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            HStack {
                ForEach(pokemon.typeNames, id: \.self) { type in
                    Chip.type(type)
                }
                Spacer()
            }
        }
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
    }
}

// MARK: - Private
private extension PokemonDetailView {
    func statsSection(pokemon: PokemonViewModel) -> some View {
        VStack(alignment: .leading) {
            ForEach(pokemon.stats) { stat in
                DetailRowStat(
                    title: stat.stat.name,
                    value: stat.baseStat,
                    textColor: textColor
                )
            }
            HStack {
                Text("Total")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(pokemon.baseStatTotal)")
            }
            .font(.pixel14)
            .padding(.top, 4)
        }
    }

    func rowSection(title: String, data: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(data)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let vm = PokemonDetailViewModel(summary: .pikachu, container: .live)
    PokemonDetailView(viewModel: vm)
        .colorScheme(.dark)
}
