enum LiveHeartRateSourceKind: Sendable {
    case appleWatch
    case chestStrap

    var selectionPriority: Int {
        switch self {
        case .appleWatch:
            return 0
        case .chestStrap:
            return 1
        }
    }
}
