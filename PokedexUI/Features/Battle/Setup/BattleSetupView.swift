import SwiftUI
import SwiftData

/// Loadout / matchup screen pushed onto the opponent-picker's navigation
/// stack inside the picker sheet. Player sees both pokemon side-by-side, a
/// type matchup summary, and a movepool grid to pick 4 moves. Tapping
/// "Battle!" emits a `BattleLaunch` upstream — the picker sheet receives it,
/// dismisses itself, and the detail view pushes `BattleView` on its own
/// nav stack. Net result: one back tap from battle returns to detail.
struct BattleSetupView: View {
    @Environment(\.container) private var container
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: BattleSetupViewModel
    /// Called when the player commits a loadout. Bubbles up through the
    /// opponent picker, which dismisses itself, then the detail view pushes
    /// the battle screen.
    private let onStart: (BattleLaunch) -> Void

    init(viewModel: BattleSetupViewModel, onStart: @escaping (BattleLaunch) -> Void) {
        self.viewModel = viewModel
        self.onStart = onStart
    }

    var body: some View {
        content
            .foregroundStyle(.white)
            .background(Color.darkGrey.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LOADOUT").font(.pixel17)
                }
            }
            .toolbarBackground(Color.darkGrey ?? .black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .task { await viewModel.prepare(modelContext: modelContext) }
    }

    /// Build the launch payload and bubble it up. The picker sheet handles
    /// its own dismissal.
    private func startBattle() {
        guard let player = viewModel.playerPokemon,
              let opponent = viewModel.opponentPokemon
        else { return }
        let launch = BattleLaunch(
            player: player,
            opponent: opponent,
            playerMoves: viewModel.playerMoves(),
            opponentMoves: viewModel.opponentMovePool
        )
        onStart(launch)
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            errorState(error)
        } else if !viewModel.isReady {
            loadingState
        } else {
            loadout
        }
    }

    // MARK: - States

    private var loadingState: some View {
        ProgressView("Preparing battle…")
            .tint(.white)
            .font(.pixel14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        Text(message)
            .font(.pixel14)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loadout

    private var loadout: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                matchupRow
                typeMatchup
                movePicker
                Spacer(minLength: 96)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
        .safeAreaBar(edge: .bottom) {
            battleButton
        }
    }

    /// Two pokemon cards side-by-side with a "VS" badge between. Each card
    /// shows sprite, name, types, and the six base stats compressed into a
    /// 3×2 grid so they fit alongside each other on phone widths.
    private var matchupRow: some View {
        HStack(alignment: .top, spacing: 8) {
            if let player = viewModel.playerPokemon {
                fighterCard(pokemon: player, summary: viewModel.playerSummary, isPlayer: true)
            }
            VStack {
                Spacer()
                Chip("VS", style: .primary, size: .medium)
                Spacer()
            }
            if let opponent = viewModel.opponentPokemon {
                fighterCard(pokemon: opponent, summary: viewModel.opponentSummary, isPlayer: false)
            }
        }
    }

    private func fighterCard(pokemon: PokemonViewModel, summary: PokemonSummary, isPlayer: Bool) -> some View {
        VStack(spacing: 8) {
            AsyncImage(url: URL(string: summary.frontSprite)) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fit)
                default: Color.clear
                }
            }
            .frame(height: 96)

            Text(summary.name)
                .font(.pixel14)
                .lineLimit(1)

            HStack(spacing: 4) {
                ForEach(pokemon.typeNames, id: \.self) { type in
                    Chip(type.uppercased())
                }
            }

            statGrid(pokemon: pokemon)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(isPlayer ? 0.08 : 0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Compact base-stat readout: HP / ATK / DEF on row 1, SPA / SPD / SPE on row 2.
    /// Numbers only — full bars belong on the detail view.
    private func statGrid(pokemon: PokemonViewModel) -> some View {
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
        .padding(.horizontal, 6)
    }

    // MARK: - Type matchup

    /// Symmetric "your offense × their defense" + reverse arrows. Player sees
    /// at a glance whether they out-type the opponent.
    private var typeMatchup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TYPE MATCHUP")
                .font(.pixel12)
                .foregroundStyle(.secondary)

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
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func matchupLine(fromName: String, fromTypes: [String], toName: String, toTypes: [String]) -> some View {
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

    private func effectivenessChipStyle(_ mult: Double) -> Chip.Style {
        switch mult {
        case 0: return .custom(background: .black.opacity(0.5))
        case let m where m >= 2: return .success
        case let m where m < 1: return .danger
        default: return .neutral
        }
    }

    private func effectivenessLabel(_ mult: Double) -> String {
        switch mult {
        case 0: return "×0"
        case let m where m >= 2: return "×\(Int(m))"
        case let m where m == 1: return "×1"
        case let m where m < 1: return "×½"
        default: return String(format: "×%.1f", mult)
        }
    }

    // MARK: - Move picker

    private var movePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("PICK \(viewModel.maxSelections) MOVES")
                    .font(.pixel12)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(viewModel.selectedMoveNames.count)/\(viewModel.maxSelections)")
                    .font(.pixel12)
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(viewModel.playerMovePool, id: \.name) { move in
                    moveCard(move)
                }
            }
        }
    }

    private func moveCard(_ move: MoveDetail) -> some View {
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

    private var battleButton: some View {
        Button {
            startBattle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                Text("BATTLE")
            }
            .font(.pixel17)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
        }
        .glassEffect(.clear.tint(.pokedexRed?.opacity(0.8)).interactive(), in: Capsule())
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .opacity(viewModel.canStart ? 1 : 0.4)
        .disabled(!viewModel.canStart)
    }
}
