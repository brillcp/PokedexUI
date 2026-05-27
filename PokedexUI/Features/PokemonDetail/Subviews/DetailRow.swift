import SwiftUI

/// Circular glass icon button used for the action row above the sprite.
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

/// Titled section with glass-effect card. Used for Data, Stats, and Evolution
/// sections in the detail view.
struct DetailSection<Content: View>: View {
    let title: String
    var tint: Color?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .frame(maxWidth: .infinity)
            content()
                .glassEffect(.clear.tint(tint), in: RoundedRectangle.card)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Generic "Label: value" row with fixed-width labels for alignment.
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

/// Labelled gauge for base stats with abbreviated stat names.
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
