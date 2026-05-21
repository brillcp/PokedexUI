import SwiftUI
import BattleKit

/// Drives `BattleView` as a conductor over engine, animator, log, and audio.
@MainActor
protocol BattleViewModelProtocol: AnyObject {
    /// Display-ready player view model.
    var playerPokemon: PokemonViewModel { get }
    /// Display-ready opponent view model.
    var opponentPokemon: PokemonViewModel { get }
    /// Sprite + HUD animation coordinator.
    var animator: BattleAnimator { get }
    /// Current battle state once initialized.
    var state: BattleState? { get }
    /// Turn resolver; `nil` until the type chart has loaded.
    var engine: BattleEngine? { get }
    /// Rendered log lines surfaced in the feed.
    var log: [AttributedString] { get }
    /// `true` while a round is being resolved.
    var isResolvingTurn: Bool { get }
    /// Winning side once the battle ends.
    var winner: BattleSide? { get }
    /// User-facing error surfaced by `prepare`.
    var errorMessage: String? { get }
    /// Player's moves for display in the move grid.
    var displayMoves: [MoveDetail] { get }

    /// Warm up battle state, sprite colors, and entrance animation.
    func prepare() async
    /// Submit a player move and resolve the round.
    func submit(_ move: MoveDetail) async
}

/// Concrete implementation of `BattleViewModelProtocol`.
@MainActor
@Observable
final class BattleViewModel {
    private let opponentMoves:      [MoveDetail]
    private let formatter:          BattleLogFormatter
    private let typeChartLoader:    TypeChartLoader
    private let audioPlayer:        AudioPlaying
    private let brain:              OpponentBrain
    private let spriteLoader:       SpriteLoading
    private let imageColorAnalyzer: ImageColorAnalyzing
    private var typeChart:          TypeChart?

    let playerPokemon:   PokemonViewModel
    let opponentPokemon: PokemonViewModel
    let animator:        BattleAnimator
    let displayMoves:    [MoveDetail]

    var engine: BattleEngine?
    var state:  BattleState?
    var log:    [AttributedString] = []
    var isResolvingTurn  = false
    var winner: BattleSide?
    var errorMessage: String?

    init(
        player: PokemonViewModel,
        opponent: PokemonViewModel,
        playerMoves: [MoveDetail],
        opponentMoves: [MoveDetail],
        container: AppContainer
    ) {
        self.playerPokemon      = player
        self.opponentPokemon    = opponent
        self.displayMoves       = playerMoves
        self.opponentMoves      = opponentMoves
        self.typeChartLoader    = container.typeChart
        self.audioPlayer        = container.audioPlayer
        self.brain              = OpponentBrain(service: container.battleAI)
        self.spriteLoader       = container.spriteLoader
        self.imageColorAnalyzer = container.imageColorAnalyzer
        self.animator           = BattleAnimator()
        self.formatter          = BattleLogFormatter(
            playerName:   player.name,
            opponentName: opponent.name
        )
        let p = BattleCombatant(pokemon: player,   moves: playerMoves.map { $0.snapshot() }, hpBonus: 1.2)
        let o = BattleCombatant(pokemon: opponent, moves: opponentMoves.map { $0.snapshot() })
        let initialState = BattleState(player: p, opponent: o)
        self.state = initialState
        if let chart = container.typeChart.chart {
            activateEngine(state: initialState, chart: chart)
        }
    }
}

// MARK: - BattleViewModelProtocol

extension BattleViewModel: BattleViewModelProtocol {
    func prepare() async {
        if engine == nil {
            await typeChartLoader.loadIfNeeded()
            guard let chart = typeChartLoader.chart, let state else {
                errorMessage = "Couldn't load type chart."
                return
            }
            activateEngine(state: state, chart: chart)
        }
        async let entrance: Void = playEntrance()
        async let colors: Void = loadSpriteColors()
        _ = await (entrance, colors)
    }

    func submit(_ move: MoveDetail) async {
        guard var eng = engine,
              let typeChart,
              !isResolvingTurn,
              winner == nil,
              let snapshot = state
        else { return }
        animator.attackTick += 1
        isResolvingTurn = true

        let opponentMove = await brain.nextMove(
            attacker:  snapshot.opponent,
            defender:  snapshot.player,
            moves:     opponentMoves,
            typeChart: typeChart
        )
        let events = eng.resolveRound(playerMove: move, opponentMove: opponentMove)
        self.engine = eng
        for event in events {
            let line = formatter.format(
                event,
                playerColor:   animator.playerCues.color,
                opponentColor: animator.opponentCues.color
            )
            log.append(line)
            #if DEBUG
            print("⚔️ \(String(line.characters))")
            #endif
            apply(event)
            await play(event)
            try? await Task.sleep(for: .milliseconds(650))
            if case .ended(let w) = event {
                winner = w ?? .player
                await playWinnerCry()
                break
            }
        }
        state = eng.state
        isResolvingTurn = false
    }
}

// MARK: - Private
private extension BattleViewModel {
    func activateEngine(state: BattleState, chart: TypeChart) {
        self.typeChart = chart
        self.engine    = BattleEngine(state: state, typeChart: chart)
    }

    func loadSpriteColors() async {
        async let playerImage   = spriteLoader.spriteImage(from: playerPokemon.frontSprite)
        async let opponentImage = spriteLoader.spriteImage(from: opponentPokemon.frontSprite)
        let (pImg, oImg) = await (playerImage, opponentImage)
        if let pImg, let color = await imageColorAnalyzer.dominantColor(for: playerPokemon.id, image: pImg) {
            animator.mutateCues(.player) { $0.color = color }
        }
        if let oImg, let color = await imageColorAnalyzer.dominantColor(for: opponentPokemon.id, image: oImg) {
            animator.mutateCues(.opponent) { $0.color = color }
        }
    }

    func playEntrance() async {
        await animator.playEntrance()
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

    func apply(_ event: BattleEvent) {
        guard var snapshot = state else { return }
        switch event {
        case .damaged(let side, let amount, _, _),
             .statusTick(let side, _, let amount),
             .recoil(let side, let amount):
            mutate(side, in: &snapshot) { $0.currentHP = max(0, $0.currentHP - amount) }
            animator.postDamage(side: side, amount: amount)
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
        case .used, .missed, .fullyParalyzed, .fastAsleep, .recharging, .lostFocus, .fainted, .ended:
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

    func play(_ event: BattleEvent) async {
        switch event {
        case .used(let side, _):
            await animator.playAttack(side: side)
        case .damaged(let side, let amount, let effectiveness, _):
            await animator.playHit(side: side, amount: amount, effectiveness: effectiveness)
        case .recoil(let side, let amount):
            await animator.playRecoil(side: side, amount: amount)
        case .fainted(let side):
            await animator.playFaint(side: side)
        default:
            break
        }
    }
}
