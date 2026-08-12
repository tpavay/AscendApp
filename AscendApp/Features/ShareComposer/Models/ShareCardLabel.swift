import Foundation

/// Where a metric's label sits relative to its value.
///
/// This is a property of the **element**, not of whichever renderer happens to
/// run. That is the whole point: before this existed, a sticker's label position
/// was accepted by the single-metric renderer and silently dropped by the
/// multi-metric one, so putting a label on the left and then adding a stat threw
/// the choice away.
enum ShareCardLabelPlacement: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Small uppercase unit under a big value — the category convention.
    case below
    /// Small uppercase label above the value.
    case above
    /// Label to the left of the value, on one line.
    case leading
    /// Label to the right of the value, on one line.
    case trailing
    /// No label, whatever the stat would otherwise offer.
    case none

    var id: String { rawValue }

    /// Cycle order for the composer's tap-to-change control.
    func next() -> ShareCardLabelPlacement {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    /// SF Symbol for the composer's placement picker.
    var symbolName: String {
        switch self {
        case .below: return "textformat.size.larger"
        case .above: return "textformat.size.smaller"
        case .leading: return "text.alignleft"
        case .trailing: return "text.alignright"
        case .none: return "textformat.slash"
        }
    }

    var displayName: String {
        switch self {
        case .below: return "Below"
        case .above: return "Above"
        case .leading: return "Left"
        case .trailing: return "Right"
        case .none: return "None"
        }
    }
}

/// Whether a metric wants a label at all.
///
/// `automatic` asks the stat itself. That replaces the old rule — "every field
/// gets a label, except one hardcoded exception written inside one view" — which
/// is why a date rendered the word `DATE` under it and why the one exception
/// that did exist leaked the moment the other renderer ran.
enum ShareCardLabelPolicy: String, CaseIterable, Codable, Sendable {
    /// Label whenever the stat has one, even if the value speaks for itself.
    case always
    /// Never label, whatever the placement says.
    case never
    /// Label only when the value is not self-describing.
    case automatic
}

extension ShareStatStickerKind {
    /// True when the value carries its own meaning, so a label beneath it is
    /// noise: a date reads as a date, a landmark name as a name, `#1` as a rank.
    ///
    /// A property of the stat, read by the one renderer — not an `if` inside a
    /// view that the other renderer never sees.
    var isSelfDescribing: Bool {
        switch self {
        case .date, .workoutName, .climbName, .climbLocation, .climbRank, .climbRankWithTotal:
            return true
        case .duration, .steps, .calories, .pace, .avgHeartRate, .maxHeartRate,
             .verticalClimb, .addedWeight, .splits, .climbFloors, .bestEffort, .totals:
            return false
        }
    }
}

extension ShareCardLabelPolicy {
    /// Resolves the policy against a stat.
    func showsLabel(for kind: ShareStatStickerKind, label: String) -> Bool {
        guard !label.isEmpty else { return false }
        switch self {
        case .always: return true
        case .never: return false
        case .automatic: return !kind.isSelfDescribing
        }
    }
}
