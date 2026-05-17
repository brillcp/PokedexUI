import SwiftUI
import SwiftData

/// Pokemon detail screen. Sprite + name + id render frame 1 from the
/// supplied `Pokemon`; the heavy body (stats, evolution, weaknesses)
/// fades in once the full `Pokemon` row is hydrated. Generic over the view
/// model protocol so tests + previews can swap in mocks.
struct PokemonDetailView<ViewModel: PokemonDetailViewModelProtocol & Sendable>: View {
    // MARK: - Environment Dependencies
    @Environment(\.container) private var container
    @Environment(\.modelContext) private var modelContext

    // MARK: - State Management
    @State private var viewModel: ViewModel
    @State private var showOpponentPicker = false
    /// Hydrated combatants + chosen movesets. Pushing this onto the nav stack
    /// shows `BattleView`. Set when the picker sheet bubbles up a loadout
    /// completion; back-from-battle is a single standard pop.
    @State private var battleLaunch: BattleLaunch?
    @State private var evolutionTarget: Pokemon?

    // MARK: - Initialization
    init(viewModel: ViewModel) {
        self.viewModel = viewModel
    }

    // MARK: - Main Body
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                spriteImage()
                loadedSection()
            }
            .animation(.linear(duration: 0.25), value: viewModel.isLoadingDetails)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .scrollIndicators(.hidden)
//        .task(id: viewModel.pokemon.id) {
//            await viewModel.loadFullDetails(
//                context: modelContext,
//                spriteLoader: container.spriteLoader
//            )
//        }
        .task(id: viewModel.pokemon.id) {
            await viewModel.loadSpritesAndColor(
                withSpriteLoader: container.spriteLoader,
                imageColorAnalyzer: container.imageColorAnalyzer
            )
        }
        .task(id: viewModel.pokemon.evolutionChainId) {
            await viewModel.loadEvolutionChain(context: modelContext)
        }
        .task { await container.typeChart.loadIfNeeded() }
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
            BattleView(
                viewModel: BattleViewModel(
                    player: launch.player,
                    opponent: launch.opponent,
                    playerMoves: launch.playerMoves,
                    opponentMoves: launch.opponentMoves,
                    typeChart: container.typeChart,
                    audioPlayer: container.audioPlayer,
                    aiService: container.battleAI
                )
            )
        }
        .navigationDestination(item: $evolutionTarget) { target in
            PokemonDetailView<PokemonDetailViewModel>(
                viewModel: PokemonDetailViewModel(summary: target)
            )
        }
        .applyDetailViewStyling(viewModel: viewModel, textColor: textColor, context: modelContext)
    }
}

// MARK: - Main Content Sections
private extension PokemonDetailView {
    var textColor: Color {
        viewModel.color?.isLight ?? false ? .black : .white
    }

    /// Everything below the sprite (action buttons + content) fades in
    /// together once the lazy pokemon hydration call resolves. Sprite stays
    /// visible from frame one (driven by `viewModel.summary`).
    @ViewBuilder
    func loadedSection() -> some View {
        let pokemon = viewModel.pokemon
        VStack(spacing: 32) {
            actionButtons(pokemon: pokemon)
            loadedContent(pokemon: pokemon)
        }
    }

    /// Renders every detail row + the stats/evolution sections once the lazy
    /// fetch resolves. Wrapped in `Group { … }.padding(...)` so the parent
    /// `contentSection()` can swap it in with an opacity transition.
    func loadedContent(pokemon: PokemonViewModel) -> some View {
        Group {
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
            GenderRow(rate: pokemon.genderRate, textColor: textColor)
            WeaknessGridView(
                pokemon: pokemon,
                typeChart: container.typeChart,
                textColor: textColor
            )

            rowSection(title: "Abilities", data: pokemon.abilities)
            rowSection(title: "Moves", data: pokemon.moves)
            statsSection(pokemon: pokemon)
            Divider().foregroundStyle(textColor)
            EvolutionChainView(
                stages: viewModel.evolutionStages,
                textColor: textColor,
                onSelect: navigateToEvolution
            )
            Spacer().frame(height: 96)
        }
        .padding(.horizontal, 24)
        .foregroundStyle(textColor)
        .lineHeight(.loose)
        .transition(.scale)
    }

    /// Top header: genus + generation badge.
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

    /// Resolve an evolution stage's species id to a stored `Pokemon`
    /// and push that pokemon's detail view. Falls back to a minimal name
    /// lookup if the summary isn't cached yet.
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

    /// "Types" row built with type-tinted chips instead of a plain string.
    /// Matches the chip style used on the fighter cards + battle HP card.
    func typesRow(pokemon: PokemonViewModel) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Types")
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(pokemon.typeNames, id: \.self) { type in
                    Chip(
                        type.uppercased(),
                        style: .custom(background: TypeColor.color(for: type))
                    )
                }
                Spacer()
            }
        }
    }

    func spriteImage() -> some View {
        (viewModel.isFlipped ? viewModel.backSprite : viewModel.frontSprite)?
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: 320)
            .modifier(Perspective3D(isFlipped: $viewModel.isFlipped))
            .animation(.bouncy(duration: 0.25, extraBounce: 0.1), value: viewModel.isFlipped)
    }
}

// MARK: - Action Buttons
private extension PokemonDetailView {
    func actionButtons(pokemon: PokemonViewModel) -> some View {
        HStack {
            DetailButton(icon: "bolt.fill") {
                showOpponentPicker = true
            }
            Spacer()
            if pokemon.latestCry != nil {
                DetailButton(icon: "speaker.wave.3.fill") {
                    Task { await viewModel.playSound(with: container.audioPlayer) }
                }
            }
            if viewModel.backSprite != nil {
                flipButton()
            }
        }
        .tint(textColor)
        .padding(.horizontal, 24)
    }

    func flipButton() -> some View {
        DetailButton(icon: "arrow.trianglehead.2.clockwise") {}
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        viewModel.flipSprite(hapticFeedback: container.haptic)
                    }
                    .onEnded { _ in
                        viewModel.flipSpriteBack(hapticFeedback: container.haptic)
                    }
            )
    }
}

// MARK: - Information Sections
private extension PokemonDetailView {
    func statsSection(pokemon: PokemonViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
                .foregroundStyle(textColor)
                .frame(height: 2)
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
    let vm = PokemonDetailViewModel(summary: .pikachu)
    PokemonDetailView(viewModel: vm)
        .colorScheme(.dark)
}
