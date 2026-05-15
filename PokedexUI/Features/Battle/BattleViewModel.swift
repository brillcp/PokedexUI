import SwiftUI

/// Drives `BattleView`. Takes fully-hydrated combatants + finalised move lists
/// from `BattleSetupViewModel` — no network or SwiftData work happens inside
/// this VM. By the time the view appears we already know everything we need
/// to start the battle; `prepare()` just builds engine state and plays the
/// entrance animation.
@MainActor
@Observable
final class BattleViewModel {
    let playerPokemon:   PokemonViewModel
    let opponentPokemon: PokemonViewModel
    /// Player's 4 hand-picked moves from the loadout screen.
    let playerMoves:     [MoveDetail]
    /// Opponent's sampled movepool (up to 40), used by the AI to pick each
    /// turn. Player never sees this list directly.
    let opponentMoves:   [MoveDetail]

    var engine: BattleEngine?
    var state:  BattleState?
    var log:    [String] = []
    var isLoadingMoves   = true
    var isResolvingTurn  = false
    var winner: BattleSide?
    var lastEvent: BattleEvent?
    var errorMessage: String?

    // Animation cues — each driven by event playback.
    var attackingSide:    BattleSide?
    var faintedSide:      BattleSide?
    var playerShakeTick:  Int = 0
    var opponentShakeTick: Int = 0
    /// Increments when the player commits a move — drives the attack-confirm haptic.
    var attackTick: Int = 0
    /// `false` while sprites are off-stage on first appear. Flipped to `true`
    /// shortly after `prepare` finishes so SwiftUI can animate them in.
    var hasEntered: Bool = false

    private let typeChart:    TypeChartLoader
    private let audioPlayer:  AudioPlayer
    private let aiService:    BattleAIServiceProtocol

    init(
        player: PokemonViewModel,
        opponent: PokemonViewModel,
        playerMoves: [MoveDetail],
        opponentMoves: [MoveDetail],
        typeChart: TypeChartLoader,
        audioPlayer: AudioPlayer,
        aiService: BattleAIServiceProtocol
    ) {
        self.playerPokemon   = player
        self.opponentPokemon = opponent
        self.playerMoves     = playerMoves
        self.opponentMoves   = opponentMoves
        self.typeChart       = typeChart
        self.audioPlayer     = audioPlayer
        self.aiService       = aiService
    }

    /// Build engine state from the pre-supplied combatants + moves and start
    /// the entrance animation. Type chart is the only thing we might still
    /// need to wait on (it's a one-time eager load, usually already done).
    func prepare() async {
        await typeChart.loadIfNeeded()
        let playerSide   = BattleCombatant(pokemon: playerPokemon,   moves: playerMoves)
        let opponentSide = BattleCombatant(pokemon: opponentPokemon, moves: opponentMoves)
        let state = BattleState(player: playerSide, opponent: opponentSide)
        self.state = state
        self.engine = BattleEngine(state: state, typeChart: typeChart)
        self.isLoadingMoves = false
        await playEntrance()
    }

    /// Brief delay, then slide both sprites in and play the opponent's cry.
    private func playEntrance() async {
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            hasEntered = true
        }
        if let cry = opponentPokemon.latestCry {
            await audioPlayer.play(from: cry)
        }
    }

    // MARK: - Round playback

    func submit(_ move: MoveDetail) async {
        guard let engine, !isResolvingTurn, winner == nil, let snapshot = state else { return }
        attackTick += 1
        isResolvingTurn = true

        // Ask the on-device AI for the opponent's move. Service falls back to
        // a random pick automatically if Apple Intelligence is unavailable or
        // the model returns garbage — so this always returns a legal move.
        let opponentMove = await aiService.chooseMove(
            attacker: snapshot.opponent,
            defender: snapshot.player,
            moves: snapshot.opponent.moves
        )
        let events = engine.resolveRound(playerMove: move, opponentMove: opponentMove)
        for event in events {
            lastEvent = event
            let line = format(event)
            log.append(line)
            #if DEBUG
            print("⚔️ \(line)")
            #endif
            apply(event)
            await playAnimation(for: event)
            try? await Task.sleep(for: .milliseconds(500))
            if case .ended(let w) = event {
                winner = w ?? .player
                await playWinnerCry()
                break
            }
        }
        state = engine.state
        isResolvingTurn = false
    }

    private func playWinnerCry() async {
        guard let winner else { return }
        let cry = winner == .player ? playerPokemon.latestCry : opponentPokemon.latestCry
        guard let cry else { return }
        try? await Task.sleep(for: .milliseconds(350))
        await audioPlayer.play(from: cry)
    }

    /// Mutate the displayed state for a single event so the HP gauge animates
    /// only after its matching log line appears.
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
            withAnimation(.easeOut(duration: 0.10)) { attackingSide = side }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { attackingSide = nil }
        case .damaged(let side, _, _, _):
            switch side {
            case .player:   playerShakeTick += 1
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

    // MARK: - Log formatting

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
