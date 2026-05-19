import SwiftUI

/// Drives `BattleView`. Takes fully-hydrated combatants and both sides'
/// finalised 4-move loadouts from `BattleSetupViewModel`. By the time we get
/// here, all preflight (hydration, move sampling, AI loadout pick) is done.
/// `prepare()` snapshots the type chart, builds engine state, and plays the
/// entrance animation.
@MainActor
@Observable
final class BattleViewModel {
    let playerPokemon:   PokemonViewModel
    let opponentPokemon: PokemonViewModel
    /// Player's 4 hand-picked moves.
    let playerMoves:     [MoveDetail]
    /// Opponent's 4 AI-picked moves.
    let opponentMoves:   [MoveDetail]

    var engine: BattleEngine?
    var state:  BattleState?
    var log:    [String] = []
    var isResolvingTurn  = false
    /// `true` while the AI is deciding the opponent's next move. Drives a
    /// "…" placeholder line in the battle log so the player sees activity
    /// during the round-trip.
    var aiThinking: Bool = false
    var winner: BattleSide?
    var lastEvent: BattleEvent?
    var errorMessage: String?

    // Animation cues. Each is driven by event playback.
    var attackingSide:    BattleSide?
    var faintedSide:      BattleSide?
    var playerShakeTick:  Int = 0
    var opponentShakeTick: Int = 0
    /// Increments when the player commits a move. Drives the attack-confirm haptic.
    var attackTick: Int = 0
    /// `false` while sprites are off-stage on first appear. Flipped to `true`
    /// shortly after `prepare` finishes so SwiftUI can animate them in.
    var hasEntered: Bool = false

    private let typeChartLoader: TypeChartLoader
    private let audioPlayer:     AudioPlayer
    private let aiService:       BattleAIServiceProtocol
    /// Captured Sendable snapshot of the type chart. Set once `prepare()`
    /// resolves the loader. AI service reads this off-main on every turn,
    /// with no actor hops.
    private var typeChart: TypeChart?
    /// Rolling window of the opponent's last few move names (oldest first).
    /// Fed into the AI prompt so it avoids repetitive play.
    private var opponentMoveHistory: [String] = []
    private let moveHistoryLimit = 4

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
        self.typeChartLoader = typeChart
        self.audioPlayer     = audioPlayer
        self.aiService       = aiService
        // Build the visible state immediately so the arena (HP cards, sprites,
        // log) renders on the very first frame. The engine, which actually
        // resolves rounds, only comes online once the type chart is
        // available; until then the move grid is disabled at the view level
        // via `engine == nil`.
        let p = BattleCombatant(pokemon: player,   moves: playerMoves)
        let o = BattleCombatant(pokemon: opponent, moves: opponentMoves)
        self.state = BattleState(player: p, opponent: o)
        // Engine fast-path: if the chart is already loaded (almost always, it
        // hydrates eagerly at app launch), wire the engine right here so the
        // move grid is tappable from frame 1.
        if let chart = typeChart.chart {
            self.typeChart = chart
            self.engine = BattleEngine(state: state!, typeChart: chart)
        }
    }

    func prepare() async {
        if engine == nil {
            // Slow-path: type chart wasn't loaded at init time. Wait for it,
            // then bring the engine online.
            await typeChartLoader.loadIfNeeded()
            guard let chart = typeChartLoader.chart, let state else {
                errorMessage = "Couldn't load type chart."
                return
            }
            self.typeChart = chart
            self.engine = BattleEngine(state: state, typeChart: chart)
        }
        await playEntrance()
    }

    // MARK: - Round playback

    func submit(_ move: MoveDetail) async {
        guard let engine,
              let typeChart,
              !isResolvingTurn,
              winner == nil,
              let snapshot = state
        else { return }
        attackTick += 1
        isResolvingTurn = true
        withAnimation(.easeInOut(duration: 0.15)) {
            aiThinking = true
        }

        // Ask the on-device AI for the opponent's move. Service falls back to
        // a random pick automatically if Apple Intelligence is unavailable or
        // the model returns garbage, so this always returns a legal move.
        let opponentMove = await aiService.chooseMove(
            attacker: snapshot.opponent,
            defender: snapshot.player,
            moves: snapshot.opponent.moves,
            typeChart: typeChart,
            recentMoves: opponentMoveHistory
        )
        opponentMoveHistory.append(opponentMove.name)
        if opponentMoveHistory.count > moveHistoryLimit {
            opponentMoveHistory.removeFirst()
        }
        withAnimation(.easeInOut(duration: 0.15)) {
            aiThinking = false
        }
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
            try? await Task.sleep(for: .milliseconds(650))
            if case .ended(let w) = event {
                winner = w ?? .player
                await playWinnerCry()
                break
            }
        }
        state = engine.state
        isResolvingTurn = false
    }
}

// MARK: - Private

private extension BattleViewModel {
    func playEntrance() async {
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
            hasEntered = true
        }
        if let cry = opponentPokemon.latestCry {
            await audioPlayer.play(from: cry)
        }
    }

    func playWinnerCry() async {
        guard let winner else { return }
        let cry = winner == .player ? playerPokemon.latestCry : opponentPokemon.latestCry
        guard let cry else { return }
        try? await Task.sleep(for: .milliseconds(350))
        await audioPlayer.play(from: cry)
    }

    /// Mutate the displayed state for a single event so the HP gauge animates
    /// only after its matching log line appears.
    func apply(_ event: BattleEvent) {
        guard var snapshot = state else { return }
        switch event {
        case .damaged(let side, let amount, _, _),
             .statusTick(let side, _, let amount),
             .recoil(let side, let amount):
            mutate(side, in: &snapshot) { $0.currentHP = max(0, $0.currentHP - amount) }
        case .healed(let side, let amount):
            mutate(side, in: &snapshot) { $0.currentHP = min($0.maxHP, $0.currentHP + amount) }
        case .statusApplied(let side, let status):
            mutate(side, in: &snapshot) {
                $0.status = status
                if status == .sleep { $0.sleepTurns = 2 }
            }
        case .wokeUp(let side):
            mutate(side, in: &snapshot) { $0.status = .none; $0.sleepTurns = 0 }
        case .statChanged(let side, let stat, let delta):
            mutate(side, in: &snapshot) { $0.applyStage(stat, delta: delta) }
        case .used, .missed, .fullyParalyzed, .fastAsleep, .fainted, .ended:
            break
        }
        state = snapshot
    }

    func mutate(_ side: BattleSide, in state: inout BattleState, _ body: (inout BattleCombatant) -> Void) {
        if side == .player {
            body(&state.player)
        } else {
            body(&state.opponent)
        }
    }

    /// Drive the per-event visual cue: attacker lunge, defender shake, faint fade.
    func playAnimation(for event: BattleEvent) async {
        switch event {
        case .used(let side, _):
            withAnimation(.easeOut(duration: 0.10)) { attackingSide = side }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { attackingSide = nil }
        case .damaged(let side, _, _, _),
             .recoil(let side, _):
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

    func name(of side: BattleSide) -> String {
        side == .player ? playerPokemon.name : opponentPokemon.name
    }

    func format(_ event: BattleEvent) -> String {
        switch event {
        case .used(let side, let moveName):
            return "\(name(of: side)) used \(moveName)!"
        case .missed(let side):
            return "\(name(of: side))'s attack missed."
        case .damaged(let side, let amount, let effectiveness, let crit):
            var line = "\(name(of: side)) took \(amount) dmg"
            if crit { line += " (critical hit!)" }
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
        case .healed(let side, let amount):
            return "\(name(of: side)) restored \(amount) HP!"
        case .recoil(let side, let amount):
            return "\(name(of: side)) took \(amount) recoil damage!"
        case .wokeUp(let side):
            return "\(name(of: side)) woke up!"
        case .fastAsleep(let side):
            return "\(name(of: side)) is fast asleep."
        case .fullyParalyzed(let side):
            return "\(name(of: side)) is fully paralyzed!"
        case .fainted(let side):
            return "\(name(of: side)) fainted!"
        case .ended(let w):
            return w.map { "\(name(of: $0)) wins!" } ?? "It's a draw."
        }
    }
}
