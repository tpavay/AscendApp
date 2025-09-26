//
//  FirebasePhotoRepository.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import Foundation
import FirebaseStorage

final class FirebasePhotoRepository: PhotoRepositoryProtocol, @unchecked Sendable {
    let firebaseStorage = Storage.storage()

    func upload(_ data: Data, filename: String) async throws -> URL {
        let storageRef = firebaseStorage.reference().child(filename)
        let _ = try await storageRef.putDataAsync(data)
        return try await storageRef.downloadURL()
    }

    func delete(url: URL) async throws {
        // Create reference from download URL
        let storageRef = try firebaseStorage.reference(for: url)
        try await storageRef.delete()
    }
}

