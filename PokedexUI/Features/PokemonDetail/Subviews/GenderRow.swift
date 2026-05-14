import SwiftUI

/// Two-tone horizontal bar showing male/female distribution from PokeAPI's
/// `gender_rate` (−1 = genderless, else `rate/8` is the female fraction).
struct GenderRow: View {
    let rate: Int
    let textColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Gender")
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .leading)
            if rate < 0 {
                Text("Genderless")
            } else {
                let female = Double(rate) / 8.0
                let male = 1.0 - female
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: proxy.size.width * male)
                            Rectangle()
                                .fill(Color.pink.opacity(0.8))
                                .frame(width: proxy.size.width * female)
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 10)
                    HStack {
                        Text("♂ \(Int(male * 100))%")
                        Spacer()
                        Text("♀ \(Int(female * 100))%")
                    }
                    .font(.pixel12)
                    .foregroundStyle(textColor.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
