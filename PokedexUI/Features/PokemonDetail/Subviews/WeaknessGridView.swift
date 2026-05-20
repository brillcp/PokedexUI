import SwiftUI

/// Bucketed type-effectiveness grid showing damage multipliers.
struct WeaknessGridView: View {
    let pokemon: PokemonViewModel
    let typeChart: TypeChartLoader
    let textColor: Color

    var body: some View {
        if buckets.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Damage Taken")
                    .foregroundStyle(.secondary)
                ForEach(buckets, id: \.label) { row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.label)
                            .frame(width: 48, alignment: .leading)
                            .foregroundStyle(textColor)
                        typeChips(row.types)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension WeaknessGridView {
    var buckets: [(label: String, types: [String])] {
        let defenders = pokemon.typeNames
        guard let chart = typeChart.chart else { return [] }

        var rows: [Double: [String]] = [:]
        for (attackerName, _) in chart.attackers {
            let m = chart.multiplier(attacking: attackerName, defenders: defenders)
            guard m != 1.0 else { continue }
            rows[m, default: []].append(attackerName)
        }
        let order: [(Double, String)] = [(4, "×4"), (2, "×2"), (0.5, "×0.5"), (0.25, "×0.25"), (0, "×0")]
        return order.compactMap { mult, label in
            guard let names = rows[mult], !names.isEmpty else { return nil }
            return (label, names.sorted())
        }
    }

    func typeChips(_ types: [String]) -> some View {
        FlowLayout(spacing: 4) {
            ForEach(types, id: \.self) { type in
                Chip(
                    type.uppercased(),
                    style: .custom(background: TypeColor.color(for: type))
                )
            }
        }
    }
}
