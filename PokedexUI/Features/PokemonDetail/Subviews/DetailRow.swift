import SwiftUI

/// Circular glass icon button used for the action row above the sprite
/// (Fight, Play Cry). Tap target padded for thumb comfort.
struct DetailButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24.0, height: 24.0)
                .padding(10)
        }
        .glassEffect(.clear.interactive(), in: Circle())
    }
}

/// Generic "Label: value" row used throughout the detail content section.
/// Label width is fixed so multiple rows align cleanly.
struct DetailRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            Text(subtitle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A labelled gauge used for the six base stats. Abbreviates long stat names
/// (`special-attack` → `SATK`) so the row fits on narrow widths.
struct DetailRowStat: View {
    let title: String
    let value: Int
    let textColor: Color

    private var abbreviatedTitle: String {
        switch title.lowercased() {
        case "special-attack": return "SATK"
        case "attack":         return "ATK"
        case "hp":             return "HP"
        case "speed":          return "SPD"
        case "special-defense": return "SDEF"
        case "defense":        return "DEF"
        default:               return title.capitalized
        }
    }

    var body: some View {
        let maxValue = max(value, 100)
        let clampedValue = max(value, 0)
        let progress = Double(clampedValue) / Double(maxValue)

        HStack {
            Text(abbreviatedTitle)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
                .lineLimit(1)
            Text("\(clampedValue)")
                .frame(width: 32)
            ProgressView(value: progress)
                .tint(textColor)
            Text("\(maxValue)")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical)
    }
}
