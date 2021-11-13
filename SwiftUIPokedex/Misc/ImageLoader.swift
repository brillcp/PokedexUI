//
//  ImageLoader.swift
//  SwiftUIPokedex
//
//  Created by Viktor Gidlöf on 2021-11-13.
//

import UIKit
import Combine

final class ImageLoader: ObservableObject {
    
    // MARK: Private properties
    private var cancellable: AnyCancellable?
    private let url: URL
    
    // MARK: - Public properties
    @Published var image: UIImage?

    // MARK: - Init
    init(url: URL) {
        self.url = url
    }
    
    deinit {
        cancel()
    }
    
    // MARK: - Public functions
    func load() {
        cancellable = URLSession.shared.dataTaskPublisher(for: url)
            .map { UIImage(data: $0.data) }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.image = $0 }
    }
    
    func cancel() {
        cancellable?.cancel()
    }
}
