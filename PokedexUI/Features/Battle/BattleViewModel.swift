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
    var log:    [AttributedString] = []
    var isResolvingTurn  = false
    /// Dominant sprite colors used to tint each pokemon's name in the log.
    /// Loaded once during `prepare`; `nil` until then. Falls back to white
    /// at render time so absent colors don't blank out the name.
    var playerColor:   Color?
    var opponentColor: Color?
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
    /// Latest damage amount + a per-side tick so the floating "-N" pop
    /// over the sprite can retrigger its animation when the same amount
    /// lands twice in a row (a fresh tick changes the SwiftUI view
    /// identity, which restarts the offset+opacity transition).
    var playerDamageAmount:   Int?
    var opponentDamageAmount: Int?
    var playerDamageTick:     Int = 0
    var opponentDamageTick:   Int = 0
    /// Increments when the player commits a move. Drives the attack-confirm haptic.
    var attackTick: Int = 0
    /// `false` while sprites are off-stage on first appear. Flipped to `true`
    /// shortly after `prepare` finishes so SwiftUI can animate them in.
    var hasEntered: Bool = false

    private let typeChartLoader: TypeChartLoader
    private let audioPlayer:     AudioPlayer
    private let aiService:       BattleAIServiceProtocol
    private let spriteLoader:    SpriteLoader
    private let imageColorAnalyzer: ImageColorAnalyzer
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
        container: AppContainer
    ) {
        self.playerPokemon      = player
        self.opponentPokemon    = opponent
        self.playerMoves        = playerMoves
        self.opponentMoves      = opponentMoves
        self.typeChartLoader    = container.typeChart
        self.audioPlayer        = container.audioPlayer
        self.aiService          = container.battleAI
        self.spriteLoader       = container.spriteLoader
        self.imageColorAnalyzer = container.imageColorAnalyzer
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
        if let chart = container.typeChart.chart {
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
        async let entrance: Void = playEntrance()
        async let colors: Void = loadSpriteColors()
        _ = await (entrance, colors)
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
    /// Resolve each combatant's dominant sprite color in parallel. The
    /// `ImageColorAnalyzer` caches by pokemon id, so a detail view that
    /// already opened the same pokemon makes this a cache hit.
    func loadSpriteColors() async {
        async let playerImage  = spriteLoader.spriteImage(from: playerPokemon.frontSprite)
        async let opponentImage = spriteLoader.spriteImage(from: opponentPokemon.frontSprite)
        let (pImg, oImg) = await (playerImage, opponentImage)
        if let pImg, let ui = await imageColorAnalyzer.dominantColor(for: playerPokemon.id, image: pImg) {
            playerColor = Color(uiColor: ui)
        }
        if let oImg, let ui = await imageColorAnalyzer.dominantColor(for: opponentPokemon.id, image: oImg) {
            opponentColor = Color(uiColor: ui)
        }
    }

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
            postDamagePopup(side: side, amount: amount)
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

    /// Surface the latest damage so the sprite can pop a floating "-N"
    /// label. Bumping the tick counter forces SwiftUI to re-fire the
    /// transition even when the previous amount matches the new one.
    func postDamagePopup(side: BattleSide, amount: Int) {
        guard amount > 0 else { return }
        switch side {
        case .player:
            playerDamageAmount = amount
            playerDamageTick += 1
        case .opponent:
            opponentDamageAmount = amount
            opponentDamageTick += 1
        }
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

    func format(_ event: BattleEvent) -> AttributedString {
        switch event {
        case .used(let side, let moveName):
            return nameAttr(side) + plain(" used ") + bold(moveName) + plain("!")
        case .missed(let side):
            return nameAttr(side) + plain("'s attack missed.")
        case .damaged(let side, let amount, let effectiveness, let crit):
            if effectiveness == 0 {
                return plain("It had no effect on ") + nameAttr(side) + plain("!")
            }
            var line = nameAttr(side) + plain(" took ") + colored("\(amount) dmg", .red)
            if crit { line += colored(" (critical hit!)", .yellow) }
            if effectiveness >= 2 { line += colored(" (super effective)", .green) }
            else if effectiveness < 1 { line += colored(" (not very effective)", .gray) }
            return line
        case .statusApplied(let side, let status):
            return nameAttr(side) + plain(" was inflicted with ") + colored(status.displayName, statusColor(status)) + plain(".")
        case .statusTick(let side, let status, let amount):
            return nameAttr(side) + plain(" hurt by ") + colored(status.displayName, statusColor(status)) + plain(" (") + colored("-\(amount)", .red) + plain(").")
        case .statChanged(let side, let stat, let delta):
            let pretty = stat.replacingOccurrences(of: "-", with: " ").capitalized
            let direction = delta > 0 ? "rose" : "fell"
            let magnitude = abs(delta) >= 2 ? " sharply" : ""
            let tint: Color = delta > 0 ? .green : .red
            return nameAttr(side) + plain("'s \(pretty)\(magnitude) ") + colored(direction, tint) + plain("!")
        case .healed(let side, let amount):
            return nameAttr(side) + plain(" restored ") + colored("\(amount) HP", .green) + plain("!")
        case .recoil(let side, let amount):
            return nameAttr(side) + plain(" took ") + colored("\(amount) recoil", .red) + plain(" damage!")
        case .wokeUp(let side):
            return nameAttr(side) + plain(" woke up!")
        case .fastAsleep(let side):
            return nameAttr(side) + plain(" is ") + colored("fast asleep", statusColor(.sleep)) + plain(".")
        case .fullyParalyzed(let side):
            return nameAttr(side) + plain(" is ") + colored("fully paralyzed", statusColor(.paralysis)) + plain("!")
        case .fainted(let side):
            return nameAttr(side) + colored(" fainted!", .red)
        case .ended(let w):
            guard let winner = w else { return plain("It's a draw.") }
            return nameAttr(winner) + colored(" wins!", .green)
        }
    }

    // MARK: - Attributed log helpers

    func nameAttr(_ side: BattleSide) -> AttributedString {
        let tint = side == .player ? (playerColor ?? .white) : (opponentColor ?? .white)
        var str = AttributedString(name(of: side))
        str.foregroundColor = tint
        return str
    }

    func plain(_ text: String) -> AttributedString {
        AttributedString(text)
    }

    func bold(_ text: String) -> AttributedString {
        var str = AttributedString(text)
        str.inlinePresentationIntent = .stronglyEmphasized
        return str
    }

    func colored(_ text: String, _ color: Color) -> AttributedString {
        var str = AttributedString(text)
        str.foregroundColor = color
        return str
    }

    func statusColor(_ status: BattleStatus) -> Color {
        switch status {
        case .none:      return .white
        case .paralysis: return .yellow
        case .burn:      return .orange
        case .poison:    return .purple
        case .sleep:     return .gray
        }
    }
}
