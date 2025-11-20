//
//  Photo.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import Foundation

enum MediaType: String, Codable {
    case photo
    case video
}

struct Photo: Identifiable, Codable {
    let id: UUID
    let url: URL
    let uploadedAt: Date
    let type: MediaType
    let duration: TimeInterval? // For videos only

    init(id: UUID = UUID(), url: URL, uploadedAt: Date = Date(), type: MediaType = .photo, duration: TimeInterval? = nil) {
        self.id = id
        self.url = url
        self.uploadedAt = uploadedAt
        self.type = type
        self.duration = duration
    }

    // Convenience initializer (what you need)
    init(url: URL, type: MediaType = .photo, duration: TimeInterval? = nil) {
        self.init(id: UUID(), url: url, uploadedAt: Date(), type: type, duration: duration)
    }
    
    var isVideo: Bool {
        return type == .video
    }
}
