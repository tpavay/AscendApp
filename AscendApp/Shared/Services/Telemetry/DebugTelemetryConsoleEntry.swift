#if DEBUG
import Foundation

struct DebugTelemetryConsoleEntry: Identifiable, Hashable {
    enum Kind: String {
        case analytics
        case breadcrumb
        case screen

        var displayName: String {
            switch self {
            case .analytics:
                "Analytics"
            case .breadcrumb:
                "Breadcrumb"
            case .screen:
                "Screen"
            }
        }
    }

    struct Parameter: Identifiable, Hashable {
        let rawKey: String
        let key: String
        let value: String
        let helpText: String?

        var id: String { rawKey }
    }

    let id = UUID()
    let kind: Kind
    let rawName: String
    let title: String
    let feature: String
    let summary: String
    let whenItFires: String
    let whyTracked: String
    let timestamp: Date
    let parameters: [Parameter]
    let environment: String?
    let destinations: [String]
    let destinationsSummary: String

    init(record: TelemetryRecord, timestamp: Date = Date()) {
        let kind: Kind = record.destinations.contains(.analytics) ? .analytics : .breadcrumb
        let metadata = Self.metadata(for: record.name, kind: kind)
        self.kind = kind
        self.rawName = record.name
        self.title = metadata.title
        self.feature = metadata.feature
        self.summary = metadata.summary
        self.whenItFires = metadata.whenItFires
        self.whyTracked = metadata.whyTracked
        self.timestamp = timestamp
        self.environment = Self.humanizedValue(for: "app_environment", value: record.parameters["app_environment"])
        self.parameters = Self.displayParameters(from: record.parameters)
        self.destinations = record.destinations
            .map(\.displayName)
            .sorted()
        self.destinationsSummary = Self.destinationsSummary(for: self.destinations)
    }

    init(screen: TelemetryScreen, timestamp: Date = Date()) {
        self.kind = .screen
        let metadata = Self.metadata(for: screen.name, kind: .screen)
        self.rawName = screen.name
        self.title = metadata.title
        self.feature = metadata.feature
        self.summary = metadata.summary
        self.whenItFires = metadata.whenItFires
        self.whyTracked = metadata.whyTracked
        self.timestamp = timestamp
        self.environment = Self.humanizedValue(for: "app_environment", value: screen.parameters["app_environment"])
        self.parameters = Self.displayParameters(from: screen.parameters)
        self.destinations = [TelemetryDestination.analytics.displayName]
        self.destinationsSummary = Self.destinationsSummary(for: self.destinations)
    }
}

private extension DebugTelemetryConsoleEntry {
    struct Metadata {
        let title: String
        let feature: String
        let summary: String
        let whenItFires: String
        let whyTracked: String
    }

    static func metadata(for rawName: String, kind: Kind) -> Metadata {
        if let known = knownMetadata[rawName] {
            return known
        }

        return Metadata(
            title: humanizedTitle(rawName),
            feature: featureName(for: rawName),
            summary: defaultSummary(for: kind),
            whenItFires: defaultWhenItFires(for: kind),
            whyTracked: defaultWhyTracked(for: kind)
        )
    }

    static func displayParameters(from rawParameters: [String: TelemetryValue]) -> [Parameter] {
        rawParameters
            .filter { $0.key != "app_environment" }
            .sorted { $0.key < $1.key }
            .map {
                Parameter(
                    rawKey: $0.key,
                    key: humanizedKey($0.key),
                    value: humanizedValue(for: $0.key, value: $0.value) ?? $0.value.stringValue,
                    helpText: parameterHelpText(for: $0.key)
                )
            }
    }

    static func destinationsSummary(for destinations: [String]) -> String {
        if destinations.isEmpty {
            return "Not sent anywhere"
        }

        if destinations.count == 1, let destination = destinations.first {
            return "Sent to \(destination)"
        }

        let allButLast = destinations.dropLast().joined(separator: ", ")
        let last = destinations.last ?? ""
        return "Sent to \(allButLast), and \(last)"
    }

    static func featureName(for rawName: String) -> String {
        if rawName.hasPrefix("auth:") {
            return "Authentication"
        }

        if rawName.hasPrefix("celebration:") {
            return "Celebration"
        }

        if rawName.contains("workout") {
            return "Workouts"
        }

        return "General"
    }

    static func humanizedTitle(_ rawName: String) -> String {
        let trimmedName = rawName
            .replacingOccurrences(of: "auth:", with: "")
            .replacingOccurrences(of: "celebration:", with: "")
            .replacingOccurrences(of: "workout_", with: "workout ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ":", with: " ")

        return trimmedName
            .split(separator: " ")
            .map { component in
                switch component.lowercased() {
                case "id":
                    return "ID"
                case "hevy":
                    return "Hevy"
                default:
                    return component.capitalized
                }
            }
            .joined(separator: " ")
    }

    static func humanizedKey(_ rawKey: String) -> String {
        switch rawKey {
        case "candidate_count_bucket":
            return "Workout Count"
        case "import_mode":
            return "Import Mode"
        case "source_mix":
            return "Source Mix"
        case "imported_count_bucket":
            return "Imported"
        case "updated_count_bucket":
            return "Updated Existing"
        case "failed_count_bucket":
            return "Failed"
        case "hevy_connected":
            return "Hevy Connected"
        case "app_environment":
            return "Environment"
        default:
            return humanizedTitle(rawKey)
        }
    }

    static func humanizedValue(for key: String, value: TelemetryValue?) -> String? {
        guard let value else { return nil }

        switch (key, value) {
        case ("app_environment", .string(let raw)),
             ("import_mode", .string(let raw)),
             ("source_mix", .string(let raw)),
             ("candidate_count_bucket", .string(let raw)),
             ("imported_count_bucket", .string(let raw)),
             ("updated_count_bucket", .string(let raw)),
             ("failed_count_bucket", .string(let raw)),
             ("outcome", .string(let raw)):
            return humanizedBucketOrEnum(raw)

        case (_, .bool(let boolean)):
            return boolean ? "Yes" : "No"

        default:
            return value.stringValue
        }
    }

    static func humanizedBucketOrEnum(_ raw: String) -> String {
        switch raw {
        case "dev":
            return "Dev"
        case "staging":
            return "Staging"
        case "production":
            return "Production"
        case "single":
            return "Single workout"
        case "selected":
            return "Selected workouts"
        case "all":
            return "Import all"
        case "automatic":
            return "Automatic import"
        case "apple_health_only":
            return "Apple Health only"
        case "hevy_only":
            return "Hevy only"
        case "linked_only":
            return "Linked Hevy + Apple Health"
        case "mixed":
            return "Mixed sources"
        case "updated_existing":
            return "Updated existing workout"
        case "partial_success":
            return "Partial success"
        case "mixed_success":
            return "Imported and updated"
        case "zero":
            return "0"
        case "one":
            return "1"
        case "2_5":
            return "2-5"
        case "6_10":
            return "6-10"
        case "11_plus":
            return "11+"
        default:
            return raw
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
        }
    }

    static func defaultSummary(for kind: Kind) -> String {
        switch kind {
        case .analytics:
            return "A product analytics event was emitted."
        case .breadcrumb:
            return "A crash breadcrumb was emitted to help explain what happened before an error."
        case .screen:
            return "A screen view was emitted for analytics."
        }
    }

    static func defaultWhenItFires(for kind: Kind) -> String {
        switch kind {
        case .analytics:
            return "This fires when a tracked product action or outcome happens in the app."
        case .breadcrumb:
            return "This fires when the app crosses a checkpoint that may help explain what happened before a crash."
        case .screen:
            return "This fires when a manually tracked screen appears on screen."
        }
    }

    static func defaultWhyTracked(for kind: Kind) -> String {
        switch kind {
        case .analytics:
            return "We track analytics to understand product usage, funnels, and outcomes."
        case .breadcrumb:
            return "We track breadcrumbs to reconstruct app state and user flow when something goes wrong."
        case .screen:
            return "We track screens to understand which surfaces are actually being opened."
        }
    }

    static func parameterHelpText(for rawKey: String) -> String? {
        switch rawKey {
        case "candidate_count_bucket":
            return "How many workout candidates were included in this import action."
        case "import_mode":
            return "Whether the user imported one workout, a selected set, everything available, or an automatic Apple Health import."
        case "source_mix":
            return "Which source combination the imported workouts came from."
        case "imported_count_bucket":
            return "How many new workouts were created by this import."
        case "updated_count_bucket":
            return "How many existing workouts were matched and updated instead of creating duplicates."
        case "failed_count_bucket":
            return "How many candidate workouts failed to import."
        case "outcome":
            return "The final result of the import flow."
        case "hevy_connected":
            return "Whether the user currently had a Hevy account connected when the screen opened."
        default:
            return nil
        }
    }

    static let knownMetadata: [String: Metadata] = [
        "auth:session_restored": Metadata(
            title: "Session Restored",
            feature: "Authentication",
            summary: "A previously signed-in user session was restored when the app launched.",
            whenItFires: "This fires on launch when Firebase restores a saved sign-in session and the user does not need to log in again.",
            whyTracked: "It confirms sign-in persistence is working and helps explain the app's auth state before a crash."
        ),
        "auth:profile_loaded": Metadata(
            title: "Profile Loaded",
            feature: "Authentication",
            summary: "The signed-in user's profile finished loading.",
            whenItFires: "This fires after auth is known and Ascend finishes loading the user's app profile data.",
            whyTracked: "It marks the point where the app has enough user data to personalize the experience."
        ),
        "auth:interactive_sign_in_success": Metadata(
            title: "Sign In Succeeded",
            feature: "Authentication",
            summary: "The user completed an Apple or Google sign-in flow.",
            whenItFires: "This fires when an Apple or Google sign-in flow finishes successfully.",
            whyTracked: "It helps measure sign-in success rate and diagnose auth funnel issues."
        ),
        "auth:sign_in_failed": Metadata(
            title: "Sign In Failed",
            feature: "Authentication",
            summary: "An Apple or Google sign-in flow failed.",
            whenItFires: "This fires when an Apple or Google sign-in attempt ends in failure.",
            whyTracked: "It helps surface auth reliability problems and provider-specific friction."
        ),
        "auth:sign_out": Metadata(
            title: "Signed Out",
            feature: "Authentication",
            summary: "The current user signed out.",
            whenItFires: "This fires when the current user signs out of Ascend.",
            whyTracked: "It helps distinguish intentional sign-out behavior from session loss or auth bugs."
        ),
        "workout_import_started": Metadata(
            title: "Workout Import Started",
            feature: "Workouts",
            summary: "The user started importing one or more workouts.",
            whenItFires: "This fires the moment the user kicks off a workout import.",
            whyTracked: "It marks the top of the import funnel and tells us which import modes people actually use."
        ),
        "workout_import_finished": Metadata(
            title: "Workout Import Finished",
            feature: "Workouts",
            summary: "The workout import flow finished and reported its final outcome.",
            whenItFires: "This fires when the import flow ends, whether it created workouts, updated existing ones, partially succeeded, or failed.",
            whyTracked: "It tells us whether imports are succeeding, where users hit failures, and how much workout data is actually getting into the app."
        ),
        "workout_import_sheet": Metadata(
            title: "Workout Import Sheet",
            feature: "Workouts",
            summary: "The workout import sheet appeared on screen.",
            whenItFires: "This fires when the workout import sheet is opened.",
            whyTracked: "It shows how often users reach the import surface, even if they do not finish an import."
        ),
        "celebration:shown": Metadata(
            title: "Celebration Shown",
            feature: "Celebration",
            summary: "A celebration flow was presented to the user.",
            whenItFires: "This fires when a celebration experience is shown.",
            whyTracked: "It helps explain user state and progression around milestone moments."
        ),
        "celebration:screen1_completed": Metadata(
            title: "Celebration Step Completed",
            feature: "Celebration",
            summary: "The first celebration step finished.",
            whenItFires: "This fires when the first step of the celebration flow completes.",
            whyTracked: "It helps measure whether users are moving through the celebration sequence."
        ),
        "celebration:screen2_completed": Metadata(
            title: "Celebration Final Step Completed",
            feature: "Celebration",
            summary: "The final celebration step finished.",
            whenItFires: "This fires when the final celebration step completes.",
            whyTracked: "It helps measure whether users finish the celebration flow."
        ),
        "celebration:dismissed": Metadata(
            title: "Celebration Dismissed",
            feature: "Celebration",
            summary: "The user dismissed a celebration flow.",
            whenItFires: "This fires when the user exits the celebration flow.",
            whyTracked: "It helps show whether users are engaging with or bailing out of celebration moments."
        ),
    ]
}
#endif
