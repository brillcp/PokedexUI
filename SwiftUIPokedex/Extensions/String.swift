//
//  String.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2025-07-12.
//

import Foundation

extension String {
    var pretty: String {
        self
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }
}
