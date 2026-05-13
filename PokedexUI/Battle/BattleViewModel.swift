import SwiftUI

@MainActor
@Observable
final class BattleViewModel {
    let playerPokemon: PokemonViewModel
    let opponentPokemon: PokemonViewModel

    var engine: BattleEngine?
    var state: BattleState?
    var log: [String] = []
    var isLoadingMoves = true
    var isResolvingTurn = false
    var winner: BattleSide?
    var lastEvent: BattleEvent?
    var errorMessage: String?

    // Animation cues — each driven by event playback.
    var attackingSide: BattleSide?
    var faintedSide: BattleSide?
    var playerShakeTick: Int = 0
    var opponentShakeTick: Int = 0
    /// Increments when the player commits a move — drives the attack-confirm haptic.
    var attackTick: Int = 0
    /// `false` while sprites are off-stage on first appear. Flipped to `true`
    /// shortly after `prepare` finishes so SwiftUI can animate them in.
    var hasEntered: Bool = false

    private let typeChart: TypeChartLoader
    private let moveService: MoveServiceProtocol

    init(
        player: PokemonViewModel,
        opponent: PokemonViewModel,
        typeChart: TypeChartLoader,
        moveService: MoveServiceProtocol = MoveService()
    ) {
        self.playerPokemon = player
        self.opponentPokemon = opponent
        self.typeChart = typeChart
        self.moveService = moveService
    }

    /// Preflight: ensure the type chart is loaded and hydrate up to 4 damaging moves per side.
    func prepare() async {
        await typeChart.loadIfNeeded()
        do {
            async let playerMoves = fetchMoves(for: playerPokemon)
            async let opponentMoves = fetchMoves(for: opponentPokemon)
            let player = BattleCombatant(pokemon: playerPokemon, moves: try await playerMoves)
            let opponent = BattleCombatant(pokemon: opponentPokemon, moves: try await opponentMoves)
            let state = BattleState(player: player, opponent: opponent)
            self.state = state
            self.engine = BattleEngine(state: state, typeChart: typeChart)
            self.isLoadingMoves = false
            await playEntrance()
        } catch {
            self.errorMessage = "Couldn't load moves: \(error.localizedDescription)"
            self.isLoadingMoves = false
        }
    }

    /// Brief delay, then slide both sprites in and play the opponent's cry.
    private func playEntrance() async {
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            hasEntered = true
        }
        if let cry = opponentPokemon.latestCry {
            await AudioPlayer.shared.play(from: cry)
        }
    }

    /// Player picked a move. Resolve a round and animate events.
    /// The engine returns the post-round state in one shot, but we want the HP bars
    /// and status pills to update *in sync with their log line*. So we keep a
    /// "displayed state" and apply each event's effect to it as we play.
    func submit(_ move: MoveDetail) async {
        guard let engine, !isResolvingTurn, winner == nil, state != nil else { return }
        attackTick += 1
        isResolvingTurn = true
        let events = engine.resolveRound(playerMove: move)
        for event in events {
            lastEvent = event
            log.append(format(event))
            apply(event)
            await playAnimation(for: event)
            try? await Task.sleep(for: .milliseconds(500))
            if case .ended(let w) = event {
                winner = w ?? .player
                await playWinnerCry()
                break
            }
        }
        // Reconcile with engine in case of drift (status flags resolved during ticks etc).
        state = engine.state
        isResolvingTurn = false
    }

    /// Brief pause so the faint event finishes its slide-off before the cry fires.
    private func playWinnerCry() async {
        guard let winner else { return }
        let pokemon = winner == .player ? playerPokemon : opponentPokemon
        guard let cry = pokemon.latestCry else { return }
        try? await Task.sleep(for: .milliseconds(350))
        await AudioPlayer.shared.play(from: cry)
    }

    /// Mutate the displayed state for a single event so the HP gauge animates only
    /// after its matching log line appears.
    private func apply(_ event: BattleEvent) {
        guard var snapshot = state else { return }
        switch event {
        case .damaged(let side, let amount, _, _),
             .statusTick(let side, _, let amount):
            mutate(side, in: &snapshot) { $0.currentHP = max(0, $0.currentHP - amount) }
        case .statusApplied(let side, let status):
            mutate(side, in: &snapshot) { $0.status = status }
        case .statChanged(let side, let stat, let delta):
            mutate(side, in: &snapshot) { $0.applyStage(stat, delta: delta) }
        case .used, .missed, .fullyParalyzed, .fainted, .ended:
            break
        }
        state = snapshot
    }

    private func mutate(_ side: BattleSide, in state: inout BattleState, _ body: (inout BattleCombatant) -> Void) {
        if side == .player {
            body(&state.player)
        } else {
            body(&state.opponent)
        }
    }

    /// Drive the per-event visual cue: attacker lunge, defender shake, faint fade.
    private func playAnimation(for event: BattleEvent) async {
        switch event {
        case .used(let side, _):
            withAnimation(.easeOut(duration: 0.15)) { attackingSide = side }
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeIn(duration: 0.15)) { attackingSide = nil }
        case .damaged(let side, _, _, _):
            switch side {
            case .player: playerShakeTick += 1
            case .opponent: opponentShakeTick += 1
            }
            try? await Task.sleep(for: .milliseconds(250))
        case .fainted(let side):
            withAnimation(.easeIn(duration: 0.5)) { faintedSide = side }
            try? await Task.sleep(for: .milliseconds(450))
        default:
            break
        }
    }

    /// Fetch up to 4 damaging moves; fall back to the first 4 known moves so status-only
    /// movesets still produce usable battle buttons.
    private func fetchMoves(for pokemon: PokemonViewModel) async throws -> [MoveDetail] {
        let names = pokemon.pokemon.moves.map { $0.move.name }
        let firstFour = Array(names.prefix(4))
        guard !firstFour.isEmpty else { return [] }
        return try await moveService.requestMoves(named: firstFour)
    }

    private func name(of side: BattleSide) -> String {
        side == .player ? playerPokemon.name : opponentPokemon.name
    }

    private func format(_ event: BattleEvent) -> String {
        switch event {
        case .used(let side, let moveName):
            return "\(name(of: side)) used \(moveName)!"
        case .missed(let side):
            return "\(name(of: side))'s attack missed."
        case .damaged(let side, let amount, let effectiveness, let crit):
            var line = "\(name(of: side)) took \(amount) dmg"
            if crit { line += " — critical hit!" }
            if effectiveness >= 2 { line += " (super effective)" }
            else if effectiveness == 0 { line = "It had no effect on \(name(of: side))!" }
            else if effectiveness < 1 { line += " (not very effective)" }
            return line
        case .statusApplied(let side, let status):
            return "\(name(of: side)) was inflicted with \(status.displayName)."
        case .statusTick(let side, let status, let amount):
            return "\(name(of: side)) hurt by \(status.displayName) (-\(amount))."
        case .statChanged(let side, let stat, let delta):
            let pretty = stat.replacingOccurrences(of: "-", with: " ").capitalized
            let direction = delta > 0 ? "rose" : "fell"
            let magnitude = abs(delta) >= 2 ? " sharply" : ""
            return "\(name(of: side))'s \(pretty)\(magnitude) \(direction)!"
        case .fullyParalyzed(let side):
            return "\(name(of: side)) is fully paralyzed!"
        case .fainted(let side):
            return "\(name(of: side)) fainted!"
        case .ended(let w):
            return w.map { "\(name(of: $0)) wins!" } ?? "It's a draw."
        }
    }
}
