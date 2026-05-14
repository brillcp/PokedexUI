import SwiftUI

/// Single tappable move card in the horizontal move grid. Equatable so only
/// the cell whose state actually changes re-renders during a battle round.
struct MoveLabel: View, Equatable {
    let name: String
    let typeName: String
    let pp: Int?
    let typeColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.pixel12)
            HStack(spacing: 8) {
                Text(typeName.uppercased())
                    .font(.pixel10)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(typeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                if let pp {
                    Text("PP \(pp)")
                        .font(.pixel12)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 8))
    }
}
