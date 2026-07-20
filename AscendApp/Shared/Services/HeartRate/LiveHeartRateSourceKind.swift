enum LiveHeartRateSourceKind: Sendable {
    case appleWatch
    case chestStrap

    /// Highest priority wins when several sources produce a fresh reading.
    /// A chest strap outranks an Apple Watch: it is the more accurate signal and
    /// the climber deliberately strapped it on. `appleWatch` is declared here so
    /// that rule is settled before a Watch source exists; none ships today.
    var selectionPriority: Int {
        switch self {
        case .appleWatch:
            return 0
        case .chestStrap:
            return 1
        }
    }
}
