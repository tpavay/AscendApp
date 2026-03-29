//
//  LeaderboardProfileSyncing.swift
//  AscendApp
//
//  Created by Codex on 3/29/26.
//

import Foundation

@MainActor
protocol LeaderboardProfileSyncing: AnyObject {
    func updateProfilePictureURL(userId: String, photoURL: URL?) async throws
}
