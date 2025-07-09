//
//  NetworkAgent.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-12.
//

import Foundation

actor NetworkService {
    private let session: URLSession = .shared

    func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
