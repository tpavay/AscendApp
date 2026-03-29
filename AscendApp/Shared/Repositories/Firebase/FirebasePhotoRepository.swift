//
//  FirebasePhotoRepository.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import Foundation
import FirebaseStorage
import UniformTypeIdentifiers

final class FirebasePhotoRepository: PhotoRepositoryProtocol, @unchecked Sendable {
    let firebaseStorage = Storage.storage()

    func upload(_ data: Data, filename: String) async throws -> URL {
        let storageRef = firebaseStorage.reference().child(filename)
        let metadata = metadata(for: filename)
        let _ = try await storageRef.putDataAsync(data, metadata: metadata)
        return try await storageRef.downloadURL()
    }

    func delete(url: URL) async throws {
        // Create reference from download URL
        let storageRef = try firebaseStorage.reference(for: url)
        try await storageRef.delete()
    }

    func delete(path: String) async throws {
        let storageRef = firebaseStorage.reference().child(path)
        try await storageRef.delete()
    }

    private func metadata(for filename: String) -> StorageMetadata {
        let metadata = StorageMetadata()
        let pathExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()

        if let mimeType = UTType(filenameExtension: pathExtension)?.preferredMIMEType {
            metadata.contentType = mimeType
            return metadata
        }

        if filename.contains("/photos/") || filename.contains("/profile_pictures/") {
            metadata.contentType = "image/jpeg"
        } else if filename.contains("/videos/") {
            metadata.contentType = "video/quicktime"
        }

        return metadata
    }
}
