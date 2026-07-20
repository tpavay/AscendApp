@MainActor
protocol LiveHeartRateSource: AnyObject {
    var sourceKind: LiveHeartRateSourceKind { get }
    var freshMeasurement: HeartRateMeasurement? { get }
    var isConnected: Bool { get }

    func prepareForLiveSession()
}
