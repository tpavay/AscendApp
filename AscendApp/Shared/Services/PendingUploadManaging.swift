//
//  PendingUploadManaging.swift
//  AscendApp
//
//  Created by Codex on 3/29/26.
//

import Foundation
import SwiftData

@MainActor
protocol PendingUploadManaging: AnyObject {
    func cancelUploads(for workoutId: UUID, modelContext: ModelContext) async
}
