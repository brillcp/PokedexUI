import SwiftUI
import SwiftData

/// Loadout screen for picking 4 moves before battle.
struct BattleSetupView<ViewModel: BattleSetupViewModelProtocol>: View {
    @Environment(\.container) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: ViewModel
    private let onStart: (BattleLaunch) -> Void

    init(viewModel: ViewModel, onStart: @escaping (BattleLaunch) -> Void) {
        self.viewModel = viewModel
        self.onStart = onStart
    }

    var body: some View {
        content
            .applyPokedexStyling(title: "Pick moves", color: .darkGrey)
            .foregroundStyle(.white)
            .task { await viewModel.prepare(modelContext: modelContext) }
    }
}

private extension BattleSetupView {
    func startBattle() {
        guard let player = viewModel.playerPokemon,
              let opponent = viewModel.opponentPokemon,
              let opponentMoves = viewModel.opponentLoadout
        else { return }
        let battleViewModel = BattleViewModel(
            player: player,
            opponent: opponent,
            playerMoves: viewModel.playerMoves(),
            opponentMoves: opponentMoves,
            container: container
        )
        onStart(BattleLaunch(viewModel: battleViewModel))
    }

    var content: some View {
        Group {
            if let error = viewModel.errorMessage {
                errorState(error)
                    .transition(.opacity)
            } else if !viewModel.isReady {
                loadingState
                    .transition(.opacity)
            } else {
                loadout
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.isReady)
        .animation(.easeInOut(duration: 0.2), value: viewModel.errorMessage)
    }

    // MARK: - States

    var loadingState: some View {
        VStack(spacing: 16) {
            PixelSpinner()
            Text("Preparing battle…")
                .font(.pixel14)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func errorState(_ message: String) -> some View {
        Text(message)
            .font(.pixel14)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loadout

    var loadout: some View {
        ScrollView(showsIndicators: false) {
            VStack {
                matchupRow
                typeMatchup
                movePicker
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaBar(edge: .bottom) { battleButton }
    }

    var matchupRow: some View {
        HStack(alignment: .top, spacing: 2) {
            if let player = viewModel.playerPokemon {
                fighterCard(pokemon: player, summary: viewModel.playerSummary)
            }
            VStack {
                Spacer()
                Chip("VS", style: .primary, size: .medium)
                Spacer()
            }
            if let opponent = viewModel.opponentPokemon {
                fighterCard(pokemon: opponent, summary: viewModel.opponentSummary)
            }
        }
    }

    func fighterCard(pokemon: PokemonViewModel, summary: Pokemon) -> some View {
        VStack(spacing: 12) {
            SpriteImage(url: summary.frontSprite)
                .frame(height: 96)

            Text(summary.name)
                .font(.pixel14)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                ForEach(pokemon.typeNames, id: \.self) { type in
                    Chip(
                        type.uppercased(),
                        style: .custom(background: TypeColor.color(for: type))
                    )
                }
            }

            statGrid(pokemon: pokemon)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cardBackground)
    }

    func statGrid(pokemon: PokemonViewModel) -> some View {
        let byName = Dictionary(uniqueKeysWithValues: pokemon.stats.map { ($0.stat.name, $0.baseStat) })
        let entries: [(String, Int)] = [
            ("HP",  byName["hp"] ?? 0),
            ("ATK", byName["attack"] ?? 0),
            ("DEF", byName["defense"] ?? 0),
            ("SPA", byName["special-attack"] ?? 0),
            ("SPD", byName["special-defense"] ?? 0),
            ("SPE", byName["speed"] ?? 0)
        ]
        return VStack(spacing: 2) {
            ForEach(0..<2) { rowIdx in
                HStack(spacing: 4) {
                    ForEach(0..<3) { colIdx in
                        let (label, value) = entries[rowIdx * 3 + colIdx]
                        HStack(spacing: 2) {
                            Text(label)
                                .foregroundStyle(.secondary)
                            Text("\(value)")
                        }
                        .font(.pixel9)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: - Type matchup

    var typeMatchup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type matchup")
                .font(.pixel12)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                matchupLine(
                    fromName: viewModel.playerSummary.name,
                    fromTypes: viewModel.playerPokemon?.typeNames ?? [],
                    toName: viewModel.opponentSummary.name,
                    toTypes: viewModel.opponentPokemon?.typeNames ?? []
                )
                matchupLine(
                    fromName: viewModel.opponentSummary.name,
                    fromTypes: viewModel.opponentPokemon?.typeNames ?? [],
                    toName: viewModel.playerSummary.name,
                    toTypes: viewModel.playerPokemon?.typeNames ?? []
                )
            }
            .padding()
            .background(Color.cardBackground)
        }
        .padding(.vertical)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func matchupLine(fromName: String, fromTypes: [String], toName: String, toTypes: [String]) -> some View {
        let multipliers = fromTypes.map { container.typeChart.multiplier(attacking: $0, defenders: toTypes) }
        let best = multipliers.max() ?? 1
        let label = effectivenessLabel(best)
        return HStack(spacing: 6) {
            Text(fromName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(toName)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Chip(label, style: effectivenessChipStyle(best))
        }
        .font(.pixel12)
    }

    func effectivenessChipStyle(_ mult: Double) -> Chip.Style {
        switch mult {
        case 0: return .custom(background: .black.opacity(0.5))
        case let m where m >= 2: return .success
        case let m where m < 1: return .danger
        default: return .neutral
        }
    }

    func effectivenessLabel(_ mult: Double) -> String {
        switch mult {
        case 0: return "×0"
        case let m where m >= 2: return "×\(Int(m))"
        case let m where m == 1: return "×1"
        case let m where m < 1: return "×1/2"
        default: return String(format: "×%.1f", mult)
        }
    }

    // MARK: - Move picker

    var movePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Pick \(viewModel.maxSelections) moves")
                    .font(.pixel12)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.selectedMoveNames.count)/\(viewModel.maxSelections)")
                    .font(.pixel12)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            let spacing: CGFloat = 2
            let columns = [
                GridItem(.flexible(), spacing: spacing),
                GridItem(.flexible(), spacing: spacing)
            ]

            LazyVGrid(
                columns: columns,
                spacing: spacing
            ) {
                ForEach(viewModel.playerMovePool, id: \.name) { move in
                    moveCard(move)
                }
            }
        }
    }

    func moveCard(_ move: MoveDetail) -> some View {
        let selected = viewModel.selectedMoveNames.contains(move.name)
        let atCap = !selected && viewModel.selectedMoveNames.count >= viewModel.maxSelections
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                viewModel.toggle(move)
            }
        } label: {
            MoveCell(move: move, mode: .loadout(selected: selected))
        }
        .buttonStyle(.plain)
        .opacity(atCap ? 0.5 : 1)
        .disabled(atCap)
    }

    // MARK: - Battle button

    @ViewBuilder
    var battleButton: some View {
        let remaining = viewModel.maxSelections - viewModel.selectedMoveNames.count
        let label = remaining > 0 ? "Pick \(remaining) \(remaining == 1 ? "move": "moves")" : "Start"
        PrimaryCapsuleButton(
            icon: "bolt.fill",
            title: label,
            isEnabled: viewModel.canStart,
            action: startBattle
        )
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: viewModel.canStart)
    }
}

#Preview {
    let player   = Pokemon.pikachu
    let opponent = Pokemon.pikachu
    let vm = BattleSetupViewModel(
        player: player,
        opponent: opponent,
        movePrefetcher: MovePrefetcher(),
        aiService: BattleAIService(),
        typeChart: TypeChartLoader()
    )
    // Pre-populate so the preview shows the loadout screen directly
    // without waiting on the network.
    let pikachuVM = PokemonViewModel(pokemon: .pikachu)
    vm.playerPokemon   = pikachuVM
    vm.opponentPokemon = pikachuVM
    let mockMoves = ["thunderbolt", "thunder-wave", "quick-attack", "iron-tail", "volt-tackle", "slam"]
    vm.playerMovePool = mockMoves.map { name in
        let m = MoveDetail(name: name)
        m.power       = name == "thunder-wave" ? nil : 80
        m.accuracy    = 100
        m.pp          = 15
        m.priority    = 0
        m.typeName    = "electric"
        m.damageClass = "special"
        return m
    }
    return NavigationStack {
        BattleSetupView(viewModel: vm, onStart: { _ in })
    }
    .colorScheme(.dark)
}
