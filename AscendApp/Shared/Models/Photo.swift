//
//  Photo.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import Foundation

struct Photo: Identifiable, Codable {
    let id: UUID
    let url: URL
    let uploadedAt: Date

    init(id: UUID = UUID(), url: URL, uploadedAt: Date = Date()) {
        self.id = id
        self.url = url
        self.uploadedAt = uploadedAt
    }

    // Convenience initializer (what you need)
    init(url: URL) {
        self.init(id: UUID(), url: url, uploadedAt: Date())
    }
}
