import SwiftUI

/// Single move cell shared by the battle grid and the loadout picker.
struct MoveCell: View, Equatable {
    let move: MoveDetail
    let mode: Mode

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

    private var header: some View {
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

    private var footer: some View {
        HStack(spacing: 12) {
            Chip(move.typeName.uppercased(), style: .custom(background: TypeColor.color(for: move.typeName)))
            switch mode {
            case .battle:
                if let pp = move.pp {
                    Text("PP \(pp)")
                        .font(.pixel12)
                        .foregroundStyle(.secondary)
                }
            case .loadout:
                Text("PWR\n\(move.power.map(String.init) ?? "-")")
                    .font(.pixel12)
                    .foregroundStyle(.secondary)
                Text("ACC\n\(move.accuracy.map { "\($0)%" } ?? "-")")
                    .font(.pixel12)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var background: AnyShapeStyle {
        switch mode {
        case .battle:
            return AnyShapeStyle(Color.cardBackground)
        case .loadout(let selected):
            let accent = Color.pokedexRed
            return AnyShapeStyle(selected ? accent.opacity(0.4) : Color.cardBackground)
        }
    }

    @ViewBuilder
    private var overlay: some View {
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
