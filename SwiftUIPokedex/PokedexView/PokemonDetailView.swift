import SwiftUI

struct PokemonDetailView<ViewModel: PokemonViewModelProtocol>: View {
    let viewModel: ViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                AsyncGridItem(viewModel: viewModel)
                    .padding(.horizontal, 44)

                ContentCard {
                    VStack {
                        BasicInfoSection(viewModel: viewModel)
                        SectionDivider()
                        StatsSection(viewModel: viewModel)
                        SectionDivider()
                        MovesSection(viewModel: viewModel)
                        BottomSpacer()
                    }
                }
            }
        }
        .applyDetailViewStyling(viewModel: viewModel)
    }
}

// MARK: - Content Sections
private extension PokemonDetailView {
    func BasicInfoSection(viewModel: ViewModel) -> some View {
        VStack {
            DetailRow(title: "Types", subtitle: viewModel.types)
            DetailRow(title: "Height", subtitle: viewModel.height)
            DetailRow(title: "Weight", subtitle: viewModel.weight)
            DetailRow(title: "Abilities", subtitle: viewModel.abilities)
        }
    }

    func StatsSection(viewModel: ViewModel) -> some View {
        ForEach(viewModel.stats) { stat in
            DetailRowStat(
                title: stat.stat.name,
                value: stat.baseStat,
                color: viewModel.color ?? .white
            )
        }
    }

    func MovesSection(viewModel: ViewModel) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Moves")
                .foregroundStyle(.secondary)
            Text(viewModel.moves)
        }
        .padding(.vertical)
    }

    func ContentCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding()
            .background(Color.darkGrey)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .foregroundStyle(.white)
    }

    func SectionDivider() -> some View {
        Divider()
            .background(.secondary)
            .padding(.vertical)
    }

    func BottomSpacer() -> some View {
        Spacer()
            .frame(height: 64)
    }
}

// MARK: - Reusable Row Components
private extension PokemonDetailView {
    func DetailRow(title: String, subtitle: String) -> some View {
        BaseRow(title: title) {
            Text(subtitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func DetailRowStat(title: String, value: Int, color: Color) -> some View {
        let clampedValue = min(max(value, 0), 100)
        return BaseRow(title: title.capitalized) {
            ProgressView(value: Double(clampedValue), total: 100)
                .frame(height: 20)
                .tint(color)
            Text("\(clampedValue) / 100")
        }
    }

    func BaseRow<Content: View>(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 96, alignment: .leading)
            content()
        }
        .padding(.vertical)
    }
}

// MARK: - View Modifiers
private extension View {
    func applyDetailViewStyling<ViewModel: PokemonViewModelProtocol>(
        viewModel: ViewModel
    ) -> some View {
        self
            .font(.pixel14)
            .foregroundColor(viewModel.isLight ? .black : .white)
            .navigationTitle(viewModel.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(viewModel.color ?? .darkGrey, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                Text("#\(viewModel.id)")
            }
            .background(viewModel.color)
            .ignoresSafeArea(edges: .bottom)
    }
}

#Preview {
    PokemonDetailView(viewModel: PokemonViewModel(pokemon: .pikachu))
}
