//
//  SheetPosition.swift
//  AscendApp
//
//  Created by Tyler Pavay on 1/15/26.
//

import SwiftUI

/// Defines the three snap positions for the draggable detail sheet
enum SheetPosition: CaseIterable, Equatable {
    case collapsed  // Photo fills ~80% of screen
    case middle     // Default - photo ~40% of screen
    case expanded   // Photo hidden, full page scroll

    /// The offset from the top of the screen for this position
    func offset(in geometry: GeometryProxy) -> CGFloat {
        let screenHeight = geometry.size.height
        switch self {
        case .collapsed:
            return screenHeight * 0.75  // Sheet at bottom 25%
        case .middle:
            return screenHeight * 0.40  // Sheet covers 60%
        case .expanded:
            return 0  // Sheet covers full screen
        }
    }

    /// The height available for the photo hero at this position
    func photoHeight(in geometry: GeometryProxy) -> CGFloat {
        let screenHeight = geometry.size.height
        switch self {
        case .collapsed:
            return screenHeight * 0.75
        case .middle:
            return screenHeight * 0.40
        case .expanded:
            return 0
        }
    }

    /// Opacity of the photo hero at this position
    var photoOpacity: Double {
        switch self {
        case .collapsed: return 1.0
        case .middle: return 1.0
        case .expanded: return 0.0
        }
    }

    /// Calculate the target position based on drag offset and velocity
    static func targetPosition(
        from currentPosition: SheetPosition,
        dragOffset: CGFloat,
        velocity: CGFloat,
        in geometry: GeometryProxy
    ) -> SheetPosition {
        let currentOffset = currentPosition.offset(in: geometry)
        let projectedOffset = currentOffset + dragOffset

        // Velocity threshold for quick flicks
        let velocityThreshold: CGFloat = 300

        // If velocity is high enough, use it to determine direction
        if abs(velocity) > velocityThreshold {
            if velocity < 0 {
                // Swiping up - go to next higher position
                return currentPosition.nextUp()
            } else {
                // Swiping down - go to next lower position
                return currentPosition.nextDown()
            }
        }

        // Otherwise, snap to nearest position based on projected offset
        let positions: [SheetPosition] = [.expanded, .middle, .collapsed]
        var closest = currentPosition
        var closestDistance = CGFloat.infinity

        for position in positions {
            let positionOffset = position.offset(in: geometry)
            let distance = abs(projectedOffset - positionOffset)
            if distance < closestDistance {
                closestDistance = distance
                closest = position
            }
        }

        return closest
    }

    /// Get the next position when dragging up
    func nextUp() -> SheetPosition {
        switch self {
        case .collapsed: return .middle
        case .middle: return .expanded
        case .expanded: return .expanded
        }
    }

    /// Get the next position when dragging down
    func nextDown() -> SheetPosition {
        switch self {
        case .collapsed: return .collapsed
        case .middle: return .collapsed
        case .expanded: return .middle
        }
    }
}
