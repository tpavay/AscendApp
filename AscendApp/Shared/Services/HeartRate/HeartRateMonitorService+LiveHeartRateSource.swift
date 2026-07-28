extension HeartRateMonitorService: LiveHeartRateSource {
    var sourceKind: LiveHeartRateSourceKind {
        .chestStrap
    }

    func prepareForLiveSession() {
        resetRejectedReadingTracking()
        autoConnectIfRemembered()
    }
}
