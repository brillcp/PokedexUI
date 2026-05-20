import SwiftUI

/// Single move cell shared by the battle grid and the loadout picker.
struct MoveCell: View, Equatable {
    let move: MoveDetail
    let mode: Mode
    let effectiveness: Double?

    init(move: MoveDetail, mode: Mode, effectiveness: Double? = nil) {
        self.move = move
        self.mode = mode
        self.effectiveness = effectiveness
    }

    enum Mode: Equatable {
        case battle
        case loadout(selected: Bool)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            footer
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(overlay)
    }
}

private extension MoveCell {
    var header: some View {
        HStack {
            Text(move.displayName)
                .font(.pixel12)
                .lineLimit(1)
            Spacer()
            if case .loadout(let selected) = mode, selected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
            }
        }
        .frame(height: 16)
    }

    var footer: some View {
        let movePower = (move.power ?? 0) > 0
        return HStack(spacing: 12) {
            Chip(move.typeName.uppercased(), style: .custom(background: TypeColor.color(for: move.typeName)))
            switch mode {
            case .battle:
                if let pp = move.pp {
                    Text("PP \(pp)")
                        .font(.pixel12)
                }
                if let effectiveness, movePower {
                    Spacer(minLength: 0)
                    Chip(effectivenessLabel(effectiveness), style: effectivenessStyle(effectiveness))
                }
            case .loadout:
                VStack {
                    Text("PWR")
                    Text("\(move.power.map(String.init) ?? "-")")
                }
                .lineLimit(1)
                .font(.pixel9)
                VStack {
                    Text("ACC")
                    Text("\(move.accuracy.map { "\($0)%" } ?? "-")")
                }
                .lineLimit(1)
                .font(.pixel9)
                if let effectiveness, movePower {
                    Spacer(minLength: 0)
                    Chip(effectivenessLabel(effectiveness), style: effectivenessStyle(effectiveness))
                }
            }
        }
        .foregroundStyle(.secondary)
    }

    func effectivenessLabel(_ mult: Double) -> String {
        switch mult {
        case 0: return "×0"
        case let m where m >= 2: return "×\(Int(m))"
        case let m where m == 1: return "×1"
        case let m where m < 1: return "×0.5"
        default: return String(format: "×%.1f", mult)
        }
    }

    func effectivenessStyle(_ mult: Double) -> Chip.Style {
        switch mult {
        case 0: return .custom(background: .black.opacity(0.5))
        case let m where m >= 2: return .success
        case let m where m < 1: return .danger
        default: return .neutral
        }
    }

    var background: AnyShapeStyle {
        switch mode {
        case .battle:
            return AnyShapeStyle(Color.cardBackground)
        case .loadout(let selected):
            let accent = Color.pokedexRed
            return AnyShapeStyle(selected ? accent.opacity(0.4) : Color.cardBackground)
        }
    }

    @ViewBuilder
    var overlay: some View {
        switch mode {
        case .battle:
            EmptyView()
        case .loadout(let selected):
            let accent = Color.pokedexRed
            Rectangle()
                .stroke(selected ? accent.opacity(0.8) : .clear, lineWidth: 1)
        }
    }
}
