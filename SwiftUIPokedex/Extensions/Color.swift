//
//  Color.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import SwiftUI

extension Color {
    
    static let darkGrey = Color(hex: "222222")
    static let pokedexRed = Color(hex: "d53b47")
    static let orange = Color(hex: "f89e2e")
    static let blue = Color(hex: "3898fe")
    static let grey = Color(hex: "8db6d2")
    static let green = Color(hex: "5ba74f")
    
    init(hex: String, alpha: CGFloat = 1.0) {
        let scanner = Scanner(string: hex)
        let hexStart = hex[hex.startIndex] == "#"
        let current = String.Index(utf16Offset: hexStart ? 1 : 0, in: hex)
        scanner.currentIndex = current
        
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0xFF00) >> 8) / 255.0
        let b = CGFloat((rgb & 0xFF)) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

extension UIColor {
    var isLight: Bool {
        guard let components = cgColor.components, components.count > 2 else { return false }
        
        let r = components[0] * 299
        let b = components[1] * 587
        let g = components[2] * 114
        
        let brightness = (r + b + g) / 1000
        return brightness > 0.7
    }
}
