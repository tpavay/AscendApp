//
//  AppleHealthAutoImportPolicy.swift
//  AscendApp
//
//  Created by Codex on 4/20/26.
//

import Foundation

struct AppleHealthAutoImportPolicy {
    let activatedAt: Date?
    let missingActivationFallback: Date?

    init(activatedAt: Date?, missingActivationFallback: Date? = nil) {
        self.activatedAt = activatedAt
        self.missingActivationFallback = missingActivationFallback
    }

    func shouldAutoImport(_ candidate: ImportedWorkoutCandidate) -> Bool {
        guard candidate.kind == .appleHealth else { return false }
        guard let sample = candidate.appleHealthSample else { return false }
        guard let activatedAt = activatedAt ?? missingActivationFallback else { return false }

        return sample.endDate >= activatedAt
    }
}
