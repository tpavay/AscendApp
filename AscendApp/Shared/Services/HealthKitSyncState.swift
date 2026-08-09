//
//  HealthKitSyncState.swift
//  AscendApp
//
//  Created by Codex on 3/11/26.
//

import Foundation

enum AppleHealthConnectionState {
    case unavailable
    case neverConnected
    case connected
    case revoked
}

enum HealthKitSyncState {
    private static let hasRequestedAuthorizationKey = "healthKit.hasRequestedAuthorization"

    static var hasRequestedAuthorization: Bool {
        get { UserDefaults.standard.bool(forKey: hasRequestedAuthorizationKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasRequestedAuthorizationKey) }
    }
}
