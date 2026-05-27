import SwiftUI

/// Horizontal evolution row with equal-width stages separated by trigger arrows.
struct EvolutionChainView: View {
    let stages: [EvolutionChain.Stage]
    let textColor: Color
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                stageCell(stage)
                    .frame(maxWidth: .infinity)
                if index < stages.count - 1 {
                    arrow(for: stages[index + 1].trigger)
                        .frame(width: 56)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

// MARK: - Private
private extension EvolutionChainView {
    func stageCell(_ stage: EvolutionChain.Stage) -> some View {
        Button {
            if let id = stage.species.id {
                onSelect(id)
            }
        } label: {
            VStack(spacing: 4) {
                if let id = stage.species.id {
                    SpriteImage(url: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(id).png")
                        .frame(width: 72, height: 72)
                }
                Text(stage.species.name.capitalized)
                    .font(.pixel12)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(stage.species.id == nil)
    }

    func arrow(for detail: EvolutionDetail?) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.right")
                .font(.pixel12)
            if let label = label(for: detail) {
                Text(label)
                    .font(.pixel9)
            }
        }
        .foregroundStyle(.secondary)
    }

    func label(for detail: EvolutionDetail?) -> String? {
        guard let detail else { return nil }
        if let level = detail.minLevel {
            return "Lv \(level)"
        }
        if let item = detail.item?.name {
            return item.replacingOccurrences(of: "-", with: " ").capitalized
        }
        if let trigger = detail.trigger?.name, trigger != "level-up" {
            return trigger.replacingOccurrences(of: "-", with: " ").capitalized
        }
        if (detail.minHappiness ?? 0) > 0 {
            return "Friendship"
        }
        return nil
    }
}
