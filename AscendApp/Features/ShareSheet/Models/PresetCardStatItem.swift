import Foundation

/// One column of a card's stat row.
struct PresetCardStatItem: Equatable, Identifiable, Sendable {
    let stat: PresetStat
    /// Small caps label under the value: `TIME`, `STEPS / MIN`, `RANK / 64`.
    let label: String
    /// `1:02:50`, `79.6`, `#7`.
    let value: String
    /// How the value reads inside a one-line summary: `79.6 spm`, `#7 of 64`.
    let inlineText: String

    var id: PresetStat { stat }
}
