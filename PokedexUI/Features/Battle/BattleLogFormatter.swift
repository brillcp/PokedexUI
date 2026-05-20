import SwiftUI

/// Pure value type that turns a `BattleEvent` into a styled
/// `AttributedString` for the log feed. Holds only the per-battle names
/// (immutable for the battle's life); sprite colors are passed per call
/// since they land asynchronously and live on `BattleAnimator` as the
/// single source of truth. Each `format(_:playerColor:opponentColor:)`
/// call is a deterministic transform with no captured state.
struct BattleLogFormatter {
    let playerName:   String
    let opponentName: String

    /// Render one battle event as a colored, partially-bolded line.
    /// Pokemon names get tinted by the supplied sprite color (falling
    /// back to white); damage / heal / status use semantic colors.
    func format(
        _ event: BattleEvent,
        playerColor: Color?,
        opponentColor: Color?
    ) -> AttributedString {
        let nameAttr = { (side: BattleSide) -> AttributedString in
            let name = side == .player ? self.playerName : self.opponentName
            let tint = (side == .player ? playerColor : opponentColor) ?? .white
            var str = AttributedString(name)
            str.foregroundColor = tint
            return str
        }
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
        case .recharging(let side):
            return nameAttr(side) + plain(" must ") + colored("recharge", .gray) + plain("!")
        case .fullyParalyzed(let side):
            return nameAttr(side) + plain(" is ") + colored("fully paralyzed", statusColor(.paralysis)) + plain("!")
        case .fainted(let side):
            return nameAttr(side) + colored(" fainted!", .red)
        case .ended(let w):
            guard let winner = w else { return plain("It's a draw.") }
            return nameAttr(winner) + colored(" wins!", .green)
        }
    }
}

// MARK: - Private

private extension BattleLogFormatter {
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
