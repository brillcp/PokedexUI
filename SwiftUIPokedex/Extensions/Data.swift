//
//  Data.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import Foundation

extension Data {
    var prettyJSON: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted])
        else { return nil }
        
        return String(data: data, encoding: .utf8)
    }
}
