//
//  VerticalClimbFunFactCard.swift
//  AscendApp
//
//  Created by Tyler Pavay on 11/26/25.
//

import SwiftUI

/// Fun fact card showing vertical climb comparison to famous landmarks
struct VerticalClimbFunFactCard: View {
    let workout: Workout
    let theme: ShareCardTheme
    let measurementSystem: MeasurementSystem
    let stepHeight: Double
    let displayName: String
    
    private var verticalClimb: Double {
        workout.totalVerticalClimb(
            stepHeight: stepHeight,
            measurementSystem: measurementSystem
        )
    }
    
    private var verticalClimbInFeet: Double {
        // Convert to feet for comparison logic
        switch measurementSystem {
        case .imperial:
            return verticalClimb
        case .metric:
            return verticalClimb * 3.28084 // meters to feet
        }
    }
    
    var body: some View {
        ShareableCardContainer(theme: theme, displayName: displayName) {
            VStack(spacing: 24) {
                // Header text
                Text("You climbed")
                    .font(.montserratMedium(size: 18))
                    .foregroundStyle(theme.secondaryTextColor)
                
                // Big number
                Text(formattedVerticalClimb)
                    .font(.montserratBold(size: 56))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                
                // Fun fact comparison
                VStack(spacing: 16) {
                    Text(comparisonText)
                        .font(.montserratSemiBold(size: 18))
                        .foregroundStyle(theme.secondaryTextColor)
                        .multilineTextAlignment(.center)
                    
                    // Landmark icon
                    landmarkIcon
                        .font(.system(size: 80))
                        .foregroundStyle(theme == .dark ? .accent : .accent.opacity(0.8))
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 40)
        }
    }
    
    private var formattedVerticalClimb: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = verticalClimb < 100 ? 1 : 0
        let value = formatter.string(from: NSNumber(value: verticalClimb)) ?? verticalClimb.formatted(.number.precision(.fractionLength(0)))
        return "\(value) \(measurementSystem.distanceAbbreviation)"
    }
    
    private var comparisonText: String {
        let comparison = LandmarkComparison.bestMatch(for: verticalClimbInFeet)
        return comparison.description
    }
    
    @ViewBuilder
    private var landmarkIcon: some View {
        let comparison = LandmarkComparison.bestMatch(for: verticalClimbInFeet)
        Image(systemName: comparison.iconName)
    }
}

// MARK: - Landmark Comparisons

private enum LandmarkComparison: CaseIterable {
    case building10Story
    case statueOfLiberty
    case bigBen
    case washingtonMonument
    case greatPyramid
    case eiffelTower
    case empireState
    case burjKhalifa
    case mountEverestBase
    
    /// Height in feet
    var heightFeet: Double {
        switch self {
        case .building10Story: return 100
        case .statueOfLiberty: return 305
        case .bigBen: return 316
        case .washingtonMonument: return 555
        case .greatPyramid: return 481
        case .eiffelTower: return 1063
        case .empireState: return 1454
        case .burjKhalifa: return 2717
        case .mountEverestBase: return 5364 // Base camp elevation gain
        }
    }
    
    var description: String {
        switch self {
        case .building10Story:
            return "That's like climbing a 10-story building!"
        case .statueOfLiberty:
            return "That's like climbing the Statue of Liberty!"
        case .bigBen:
            return "That's like climbing Big Ben!"
        case .washingtonMonument:
            return "That's like climbing the Washington Monument!"
        case .greatPyramid:
            return "That's like climbing the Great Pyramid of Giza!"
        case .eiffelTower:
            return "That's like climbing the Eiffel Tower!"
        case .empireState:
            return "That's like climbing the Empire State Building!"
        case .burjKhalifa:
            return "That's like climbing the Burj Khalifa!"
        case .mountEverestBase:
            return "That's like hiking to Everest Base Camp!"
        }
    }
    
    var iconName: String {
        switch self {
        case .building10Story:
            return "building.2.fill"
        case .statueOfLiberty:
            return "figure.arms.open"
        case .bigBen:
            return "clock.fill"
        case .washingtonMonument:
            return "obelisk.fill"
        case .greatPyramid:
            return "pyramid.fill"
        case .eiffelTower:
            return "antenna.radiowaves.left.and.right"
        case .empireState:
            return "building.fill"
        case .burjKhalifa:
            return "building.columns.fill"
        case .mountEverestBase:
            return "mountain.2.fill"
        }
    }
    
    /// Find the best matching landmark for a given climb height
    static func bestMatch(for heightFeet: Double) -> LandmarkComparison {
        // Sort by height and find the closest match
        let sorted = allCases.sorted { $0.heightFeet < $1.heightFeet }
        
        // Find the landmark closest to but not exceeding the climb height
        // If climb is very small, use the first one
        var bestMatch: LandmarkComparison = .building10Story
        
        for landmark in sorted {
            if heightFeet >= landmark.heightFeet * 0.7 {
                bestMatch = landmark
            }
        }
        
        return bestMatch
    }
}

#Preview("Dark Theme - Small Climb") {
    let workout = Workout(
        name: "Quick Session",
        duration: 600,
        steps: 500,
        floors: 31,
        stepsPerFloor: 16
    )
    
    return VerticalClimbFunFactCard(
        workout: workout,
        theme: .dark,
        measurementSystem: .imperial,
        stepHeight: 0.18,
        displayName: "tpavay"
    )
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Light Theme - Medium Climb") {
    let workout = Workout(
        name: "Morning Session",
        duration: 1800,
        steps: 2500,
        floors: 156,
        stepsPerFloor: 16
    )
    
    return VerticalClimbFunFactCard(
        workout: workout,
        theme: .light,
        measurementSystem: .imperial,
        stepHeight: 0.18,
        displayName: "tpavay"
    )
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}

#Preview("Dark Theme - Large Climb") {
    let workout = Workout(
        name: "Epic Climb",
        duration: 7200,
        steps: 10000,
        floors: 625,
        stepsPerFloor: 16
    )
    
    return VerticalClimbFunFactCard(
        workout: workout,
        theme: .dark,
        measurementSystem: .imperial,
        stepHeight: 0.18,
        displayName: "tpavay"
    )
    .frame(width: WorkoutShareCarouselViewModel.displayCardWidth)
    .padding()
    .background(Color.gray.opacity(0.2))
}

