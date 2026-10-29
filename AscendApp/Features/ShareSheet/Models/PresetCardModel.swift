import Foundation

/// Everything one Presets card draws, decided before any view sees it.
struct PresetCardModel: Equatable, Sendable {
    let subject: ShareSheetSubject
    let layout: PresetLayout
    let background: PresetCardBackground
    let font: PresetFont
    let accent: PresetAccent
    let palette: PresetCardPalette
    /// The switched-on stats that fit the row, in pool order. Steps is always shown separately.
    let stats: [PresetCardStatItem]
    let bestEffort: ShareBestEffortDisplay
    /// The small caps line above the headline number: the climb label, or a seasonal caption.
    let label: String

    init(
        subject: ShareSheetSubject,
        preferences: PresetPreferences,
        layout: PresetLayout,
        background: PresetCardBackground,
        pickedBestEffortID: String? = nil,
        copyYear: Int
    ) {
        self.subject = subject
        self.layout = layout
        self.background = background
        self.font = preferences.font
        self.accent = preferences.accent
        self.palette = PresetCardPalette(accent: preferences.accent, background: background)
        self.stats = Self.statItems(subject: subject, preferences: preferences)
        self.bestEffort = ShareBestEffortDisplay.resolve(
            efforts: subject.bestEfforts,
            isOn: preferences.isOn(.bestEfforts),
            pickedID: pickedBestEffortID
        )
        if case .seasonal(let seasonal) = background {
            self.label = seasonal.caption(year: copyYear)
        } else {
            self.label = subject.label
        }
    }

    /// The stats a climber can switch on for this climb: Floors and Avg HR only when the climb has
    /// them, Rank only when a finish rank exists.
    static func availableStats(for subject: ShareSheetSubject) -> [PresetStat] {
        PresetStat.allCases.filter { stat in
            switch stat {
            case .time, .stepsPerMinute: return true
            case .floors: return subject.floorsText != nil
            case .averageHeartRate: return subject.hasHeartRate
            case .rank: return subject.hasRank
            case .bestEfforts: return !subject.bestEfforts.isEmpty
            }
        }
    }

    static func statItems(subject: ShareSheetSubject, preferences: PresetPreferences) -> [PresetCardStatItem] {
        var items: [PresetCardStatItem] = []
        for stat in availableStats(for: subject) where stat.isRowStat && preferences.isOn(stat) {
            switch stat {
            case .time:
                items.append(.init(stat: stat, label: "TIME", value: subject.durationText, inlineText: subject.durationText))
            case .stepsPerMinute:
                items.append(.init(stat: stat, label: "STEPS / MIN", value: subject.stepsPerMinuteText, inlineText: "\(subject.stepsPerMinuteText) spm"))
            case .floors:
                if let floors = subject.floorsText {
                    items.append(.init(stat: stat, label: "FLOORS", value: floors, inlineText: "\(floors) floors"))
                }
            case .averageHeartRate:
                if let average = subject.averageHeartRate {
                    items.append(.init(stat: stat, label: "AVG BPM", value: "\(average)", inlineText: "\(average) bpm"))
                }
            case .rank:
                if let rank = subject.rank {
                    items.append(.init(stat: stat, label: "RANK / \(rank.fieldText)", value: "#\(rank.positionText)", inlineText: "#\(rank.positionText) of \(rank.fieldText)"))
                }
            case .bestEfforts:
                break
            }
        }
        return items
    }

    /// `5,004 steps · 1:02:50 · 79.6 spm`, the Minimal layout's one line.
    var minimalLine: String {
        ([ "\(subject.stepsText) steps" ] + stats.map(\.inlineText)).joined(separator: " · ")
    }

    /// Steps plus up to three stats, as the Grid layout's cells.
    var gridStats: [PresetCardStatItem] {
        Array(stats.prefix(3))
    }

    /// The count `n` of the earned best efforts, or nil when none show.
    var hasBestEffortBadge: Bool {
        bestEffort != .none
    }
}
