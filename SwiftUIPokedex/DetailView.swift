//
//  DetailView.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import SwiftUI

struct DetailView<ViewModel: PokemonViewModelProtocol>: View {
    var viewModel: ViewModel

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let safeArea = geometry.safeAreaInsets.top
                ScrollView {
                    VStack {
                        AsyncGridItem(viewModel: viewModel)

                        VStack {
                            detailRow(
                                title: "Types",
                                subtitle: viewModel.types
                            )
                            detailRow(
                                title: "Height",
                                subtitle: viewModel.height
                            )
                            detailRow(
                                title: "Weight", 
                                subtitle: viewModel.weight
                            )
                            detailRow(
                                title: "Abilities",
                                subtitle: viewModel.abilities
                            )

                            Divider()
                                .background(.secondary)

                            ForEach(viewModel.stats) {
                                detailRowStat(
                                    title: $0.stat.name,
                                    value: $0.baseStat,
                                    color: viewModel.color ?? .white
                                )
                            }

                            Divider()
                                .background(.secondary)

                            VStack(alignment: .leading, spacing: 16.0) {
                                Text("Moves")
                                    .foregroundStyle(.secondary)
                                Text(viewModel.moves)
                            }
                            .padding(.vertical)

                            Spacer()
                                .frame(height: 64)
                        }
                        .padding()
                        .background(Color.darkGrey)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                        .foregroundStyle(.white)
                    }
                }
                .font(.pixel14)
                .foregroundColor(viewModel.isLight ? .black : .white)
                .navigationTitle(viewModel.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    Text("#\(viewModel.id)")
                }
                .background(viewModel.color)
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - Private functions
private extension DetailView {
    func detailRow(title: String, subtitle: String) -> some View {
        row(title: title) {
            Text(subtitle)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func detailRowStat(title: String, value: Int, color: Color) -> some View {
        row(title: title.capitalized) {
            ProgressView(value: Double(value), total: 100)
                .frame(height: 20)
                .tint(color)
            Text("\(value) / 100")
        }
    }

    func row<Content: View>(title: String, @ViewBuilder content: @escaping  () -> Content) -> some View {
        HStack(spacing: 20) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 96, alignment: .leading)
            content()
        }
        .padding(.vertical)
    }
}

#Preview {
    DetailView(viewModel: PokemonViewModel(pokemon: .pikachu))
}
