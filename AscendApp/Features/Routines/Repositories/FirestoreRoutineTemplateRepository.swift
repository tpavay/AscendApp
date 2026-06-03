import Foundation
@preconcurrency import FirebaseFirestore

final class FirestoreRoutineTemplateRepository: RoutineTemplateRepository, @unchecked Sendable {
    static let shared = FirestoreRoutineTemplateRepository()

    private let db = Firestore.firestore()

    private init() {}

    func fetchPublishedTemplates() async throws -> [RemoteRoutineTemplate] {
        let snapshot = try await db.collection("routine_templates")
            .whereField("status", isEqualTo: "published")
            .getDocuments(source: .server)

        return snapshot.documents
            .compactMap { parseTemplate(documentId: $0.documentID, data: $0.data()) }
            .filter {
                isSupported(
                    minAppVersion: stringValue(for: "minAppVersion", in: $0.rawData)
                        ?? stringValue(for: "min_app_version", in: $0.rawData)
                )
            }
            .sorted { lhs, rhs in
                if lhs.displayOrder != rhs.displayOrder {
                    return lhs.displayOrder < rhs.displayOrder
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            .map(\.template)
    }

    private func parseTemplate(
        documentId: String,
        data: [String: Any]
    ) -> ParsedRemoteRoutineTemplate? {
        guard stringValue(for: "status", in: data) == "published",
              let name = stringValue(for: "name", in: data)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let intervalRows = data["intervals"] as? [[String: Any]],
              !intervalRows.isEmpty else {
            return nil
        }

        let intervals = intervalRows.compactMap(parseInterval)
        guard !intervals.isEmpty else { return nil }

        let displayOrder = intValue(for: "displayOrder", in: data)
            ?? intValue(for: "display_order", in: data)
            ?? 0
        let featuredOrder = intValue(for: "featuredOrder", in: data)
            ?? intValue(for: "featured_order", in: data)
        let isFeatured = boolValue(for: "isFeatured", in: data)
            ?? boolValue(for: "is_featured", in: data)
            ?? (featuredOrder != nil)
        let browseSections = (stringArrayValue(for: "browseSections", in: data)
            ?? stringArrayValue(for: "browse_sections", in: data))?
            .compactMap(BuiltInRoutineBrowseSection.remoteValue) ?? []

        return ParsedRemoteRoutineTemplate(
            rawData: data,
            template: RemoteRoutineTemplate(
                id: stringValue(for: "templateId", in: data) ?? documentId,
                version: intValue(for: "version", in: data),
                name: name,
                routineDescription: stringValue(for: "description", in: data)
                    ?? stringValue(for: "routineDescription", in: data)
                    ?? "",
                intervals: intervals,
                browseSections: browseSections,
                isFeatured: isFeatured,
                displayOrder: displayOrder,
                featuredOrder: featuredOrder,
                difficulty: intValue(for: "difficulty", in: data),
                estimatedCalories: intValue(for: "estimatedCalories", in: data)
                    ?? intValue(for: "estimated_calories", in: data),
                updatedAt: dateValue(for: "updatedAt", in: data)
                    ?? dateValue(for: "updated_at", in: data)
            )
        )
    }

    private func parseInterval(_ data: [String: Any]) -> RemoteRoutineTemplateInterval? {
        let duration = doubleValue(for: "durationSeconds", in: data)
            ?? doubleValue(for: "duration_seconds", in: data)
            ?? doubleValue(for: "duration", in: data)
        guard let duration,
              duration > 0,
              let intensity = parseIntensity(data) else {
            return nil
        }

        return RemoteRoutineTemplateInterval(
            duration: duration,
            intensity: intensity,
            modifiers: parseModifiers(data["modifiers"] as? [String: Any] ?? data)
        )
    }

    private func parseIntensity(_ data: [String: Any]) -> RemoteRoutineTemplateInterval.Intensity? {
        if let zoneRawValue = stringValue(for: "zone", in: data),
           let zone = ClimbZone(rawValue: zoneRawValue) {
            return .zone(zone)
        }

        let rawType = stringValue(for: "intensityType", in: data)
            ?? stringValue(for: "intensity_type", in: data)
            ?? (data["spm"] != nil ? "spm" : nil)
            ?? (data["level"] != nil ? "level" : nil)
            ?? IntensityType.level.rawValue
        let normalizedType = rawType.lowercased()

        switch normalizedType {
        case "level":
            guard let level = intValue(for: "intensityValue", in: data)
                ?? intValue(for: "intensity_value", in: data)
                ?? intValue(for: "level", in: data) else {
                return nil
            }
            return .level(level)
        case "stepsperminute", "steps_per_minute", "spm":
            guard let spm = intValue(for: "intensityValue", in: data)
                ?? intValue(for: "intensity_value", in: data)
                ?? intValue(for: "spm", in: data) else {
                return nil
            }
            return .stepsPerMinute(spm)
        default:
            return nil
        }
    }

    private func parseModifiers(_ data: [String: Any]) -> IntervalModifiers {
        IntervalModifiers(
            sidewaysDirection: stringValue(for: "sidewaysDirection", in: data)
                .flatMap(SidewaysDirection.init(rawValue:))
                ?? stringValue(for: "sideways_direction", in: data)
                .flatMap(SidewaysDirection.init(rawValue:)),
            skipStep: boolValue(for: "skipStep", in: data)
                ?? boolValue(for: "skip_step", in: data)
                ?? false,
            backwardStep: boolValue(for: "backwardStep", in: data)
                ?? boolValue(for: "backward_step", in: data)
                ?? false,
            holdingBars: boolValue(for: "holdingBars", in: data)
                ?? boolValue(for: "holding_bars", in: data)
                ?? false
        )
    }

    private func isSupported(minAppVersion: String?) -> Bool {
        guard let minAppVersion,
              !minAppVersion.isEmpty else {
            return true
        }

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return compareVersion(currentVersion, minAppVersion) != .orderedAscending
    }

    private func compareVersion(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0

            if lhsValue < rhsValue { return .orderedAscending }
            if lhsValue > rhsValue { return .orderedDescending }
        }

        return .orderedSame
    }

    private func stringValue(for key: String, in data: [String: Any]) -> String? {
        data[key] as? String
    }

    private func stringArrayValue(for key: String, in data: [String: Any]) -> [String]? {
        data[key] as? [String]
    }

    private func intValue(for key: String, in data: [String: Any]) -> Int? {
        if let value = data[key] as? Int {
            return value
        }

        if let value = data[key] as? Double {
            return Int(value)
        }

        if let value = data[key] as? NSNumber {
            return value.intValue
        }

        return nil
    }

    private func doubleValue(for key: String, in data: [String: Any]) -> Double? {
        if let value = data[key] as? Double {
            return value
        }

        if let value = data[key] as? Int {
            return Double(value)
        }

        if let value = data[key] as? NSNumber {
            return value.doubleValue
        }

        return nil
    }

    private func boolValue(for key: String, in data: [String: Any]) -> Bool? {
        if let value = data[key] as? Bool {
            return value
        }

        if let value = data[key] as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    private func dateValue(for key: String, in data: [String: Any]) -> Date? {
        if let value = data[key] as? Timestamp {
            return value.dateValue()
        }

        return data[key] as? Date
    }
}

private struct ParsedRemoteRoutineTemplate {
    let rawData: [String: Any]
    let template: RemoteRoutineTemplate

    var displayOrder: Int {
        template.displayOrder
    }

    var name: String {
        template.name
    }
}
