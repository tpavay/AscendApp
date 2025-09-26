//
//  PhotoRepositoryProtocol.swift
//  AscendApp
//
//  Created by Tyler Pavay on 9/20/25.
//

import Foundation

protocol PhotoRepositoryProtocol: Sendable {
    func upload(_ data: Data, filename: String) async throws -> URL
    func delete(url: URL) async throws
}
