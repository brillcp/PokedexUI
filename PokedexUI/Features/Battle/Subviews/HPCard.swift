import SwiftUI

/// Name, status pill, HP gauge and HP text for one combatant. Equatable so
/// SwiftUI's diffing can skip re-rendering the other side's card during
/// per-event animations.
struct HPCard: View, Equatable {
    let name: String
    let currentHP: Int
    let maxHP: Int
    let status: BattleStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name).font(.pixel14)
                if status != .none {
                    Chip(status.displayName, style: .custom(background: statusColor.opacity(0.4), foreground: statusColor))
                }
            }
            ProgressView(value: Double(currentHP), total: Double(maxHP))
                .tint(hpTint)
                .animation(.easeOut(duration: 0.4), value: currentHP)
            Text("\(currentHP) / \(maxHP)")
                .font(.pixel12)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(currentHP)))
                .animation(.easeOut(duration: 0.4), value: currentHP)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .glassEffect(.clear, in: RoundedRectangle.card)
    }

    private var hpTint: Color {
        let ratio = Double(currentHP) / Double(maxHP)
        if ratio > 0.5 { return .green }
        if ratio > 0.2 { return .yellow }
        return .red
    }

    private var statusColor: Color {
        switch status {
        case .paralysis: return .yellow
        case .burn:      return .orange
        case .poison:    return .purple
        case .sleep:     return .gray
        case .none:      return .clear
        }
    }
}
