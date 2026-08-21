import Foundation

enum OnboardingAnalyticsUserProperties {
    static func setSurveyAnswer(questionID: String, selectedOptionIDs: Set<String>) {
        let sortedOptionIDs = selectedOptionIDs.sorted()
        guard !sortedOptionIDs.isEmpty else { return }

        switch questionID {
        case "stair_stepper_baseline":
            set("stair_stepper_exp", sortedOptionIDs[0])
        case "exercise_level":
            set("exercise_level", sortedOptionIDs[0])
        case "goal":
            setGoalProperties(selectedOptionIDs: selectedOptionIDs)
        case "motivation":
            set("motivation", sortedOptionIDs[0])
        case "plan":
            set("planned_frequency", sortedOptionIDs[0])
        default:
            break
        }
    }

    static func setGender(_ gender: ProfileGender) {
        set("profile_gender", gender.rawValue)
    }

    static func setAgeGroup(age: Int) {
        set("profile_age_group", ageGroupValue(for: age))
    }

    static func setWeightGroup(weightKg: Double) {
        set("profile_weight_group", weightGroupValue(forWeightKg: weightKg))
    }

    static func ageGroupValue(for age: Int) -> String {
        switch age {
        case 13...17:
            return "13_17"
        case 18...24:
            return "18_24"
        case 25...29:
            return "25_29"
        case 30...34:
            return "30_34"
        case 35...39:
            return "35_39"
        case 40...44:
            return "40_44"
        case 45...49:
            return "45_49"
        case 50...54:
            return "50_54"
        case 55...59:
            return "55_59"
        case 60...64:
            return "60_64"
        case 65...:
            return "65_plus"
        default:
            return "unknown"
        }
    }

    static func weightGroupValue(forWeightKg weightKg: Double) -> String {
        let pounds = weightKg * 2.2046226218

        switch pounds {
        case ..<150:
            return "under_150_lb"
        case 150..<200:
            return "150_199_lb"
        case 200..<250:
            return "200_249_lb"
        default:
            return "250_plus_lb"
        }
    }

    static func heightGroupValue(forHeightCm heightCm: Double) -> String {
        switch heightCm {
        case ..<150:
            return "under_150_cm"
        case 150..<165:
            return "150_164_cm"
        case 165..<180:
            return "165_179_cm"
        case 180..<195:
            return "180_194_cm"
        default:
            return "195_plus_cm"
        }
    }

    static func setLocationCountry(_ countryCode: String) {
        set("profile_country", countryCode.uppercased())
        set("profile_location_set", "true")
    }

    static func setNotificationChoice(_ choice: String) {
        set("notifications_choice", choice)
    }

    static func setFirstClimb(_ climb: Climb) {
        set("first_climb_id", climb.id)
        set("first_climb_tier", climb.tier.rawValue)
        set("first_climb_steps", stepBucket(for: climb.referenceStepCount))
    }

    static func setOnboardingCompleted() {
        set("onboarding_complete", "true")
    }

    private static func setGoalProperties(selectedOptionIDs: Set<String>) {
        let knownGoalProperties: [String: String] = [
            "lose_weight": "goal_lose_weight",
            "build_endurance": "goal_build_endurance",
            "track_progress": "goal_track_progress",
            "exciting_workouts": "goal_exciting_workouts",
            "healthier_life": "goal_healthier_life"
        ]

        for (optionID, propertyName) in knownGoalProperties {
            set(propertyName, selectedOptionIDs.contains(optionID) ? "true" : "false")
        }

        set("goal_answer_count", "\(selectedOptionIDs.count)")
    }

    private static func stepBucket(for steps: Int) -> String {
        switch steps {
        case ..<250:
            return "under_250"
        case 250..<500:
            return "250_499"
        case 500..<1_000:
            return "500_999"
        case 1_000..<2_000:
            return "1000_1999"
        case 2_000..<5_000:
            return "2000_4999"
        default:
            return "5000_plus"
        }
    }

    private static func set(_ name: String, _ value: String) {
        TelemetryManager.shared.setUserProperty(name, value: value)
    }
}
