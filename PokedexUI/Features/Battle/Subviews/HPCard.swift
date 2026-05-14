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
                    Text(status.displayName)
                        .font(.pixel10)
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 4))
                }
            }
            Gauge(value: Double(currentHP), in: 0...Double(maxHP)) {
                EmptyView()
            } currentValueLabel: { EmptyView() }
            .gaugeStyle(.linearCapacity)
            .tint(hpTint)
            .animation(.easeOut(duration: 0.5), value: currentHP)
            Text("\(currentHP) / \(maxHP)")
                .font(.pixel12)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(currentHP)))
                .animation(.easeOut(duration: 0.5), value: currentHP)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(width: 180, alignment: .leading)
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 8))
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
        case .none:      return .clear
        }
    }
}
