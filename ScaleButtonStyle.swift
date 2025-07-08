//
//  ScaleButtonStyle.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2025-07-08.
//

import SwiftUI

struct ScaleButtonStyle: ButtonStyle {
    private let minDistance: CGFloat = 0.8

    @GestureState private var isPressed: Bool = false
    @State private var scale: CGFloat = 1.0

    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .scaleEffect(scale)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                            scale = abs(value.translation.height) < minDistance ? 0.97 : 1.0
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                            scale = 1.0
                        }
                    }
            )
    }
}
