import SwiftUI

/// Single move cell shared by the battle move grid and the loadout move
/// picker. Both surfaces show: name + colored type chip. The mode flag
/// switches the trailing metadata (PP for battle, power/accuracy for
/// loadout) and whether the cell renders a selected checkmark / accent
/// background (loadout only).
struct MoveCell: View, Equatable {
    let move: MoveDetail
    let mode: Mode

    /// Switches the trailing metadata + selection styling. Battle cells show
    /// PP; loadout cells show power/accuracy and render a selected outline.
    enum Mode: Equatable {
        /// In-battle move button. Shows PP, no selection state.
        case battle
        /// Loadout picker cell. Shows PWR/ACC, draws a selected outline and
        /// fill when `selected` is true.
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

    // MARK: - Sections

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

    // MARK: - Styling

    private var background: AnyShapeStyle {
        switch mode {
        case .battle:
            return AnyShapeStyle(Color.cardBackground)
        case .loadout(let selected):
            let accent = Color.pokedexRed ?? .red
            return AnyShapeStyle(selected ? accent.opacity(0.4) : Color.cardBackground)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch mode {
        case .battle:
            EmptyView()
        case .loadout(let selected):
            let accent = Color.pokedexRed ?? .red
            Rectangle()
                .stroke(selected ? accent.opacity(0.8) : .clear, lineWidth: 1)
        }
    }
}
