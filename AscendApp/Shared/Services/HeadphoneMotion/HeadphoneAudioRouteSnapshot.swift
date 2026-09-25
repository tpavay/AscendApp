import AVFoundation

/// Best-effort classification of the connected audio output's headphone family, read from
/// `AVAudioSession.currentRoute`. iOS exposes no reliable public API for exact AirPods/Beats
/// generation, so this never attempts one - `family` is the coarsest bucket determinable from
/// the route's own `portName`, and generation is always left unstated.
enum HeadphoneFamily: String, Codable, Sendable, CaseIterable {
    /// No headphone-class output connected (built-in speaker/receiver, car audio, etc).
    case none
    case airPodsPro = "airpods_pro"
    case airPodsMax = "airpods_max"
    case airPods = "airpods"
    case beats
    /// A recognized headphone-class output whose name doesn't match a known Apple pattern -
    /// third-party headphones, or an Apple device renamed beyond recognition.
    case other
    /// A headphone-class output was connected but its name gave nothing to classify from.
    case unknown
}

/// A point-in-time read of the connected audio output, captured once when a climb is saved.
/// `rawPortName` and `rawPortType` are stored verbatim with the climb record for the captain's
/// own step-accuracy investigation - see `HeadphoneMotionWorkoutMetadata`. They are never sent
/// to analytics: a Bluetooth accessory's name commonly carries the climber's own name (iOS
/// defaults to "<Owner>'s AirPods Pro"), so only `family` and `isHeadphoneClassOutputConnected`
/// - both low-cardinality - reach `WorkoutStepAccuracyAnalyticsEvent`.
struct HeadphoneAudioRouteSnapshot: Codable, Equatable, Sendable {
    let rawPortName: String?
    let rawPortType: String?
    let family: HeadphoneFamily
    /// Whether the connected output is a headphone-class device at all (Bluetooth or wired
    /// headset), independent of whether it happens to support headphone motion.
    let isHeadphoneClassOutputConnected: Bool

    /// Longest raw port name stored. A Bluetooth name is user-set and can run to ~248 bytes,
    /// which would spend a large share of `sourceMetadata`'s budget on the least useful field.
    static let maximumRawPortNameLength = 64

    init(
        rawPortName: String?,
        rawPortType: String?,
        family: HeadphoneFamily,
        isHeadphoneClassOutputConnected: Bool
    ) {
        self.rawPortName = rawPortName.map { String($0.prefix(Self.maximumRawPortNameLength)) }
        self.rawPortType = rawPortType
        self.family = family
        self.isHeadphoneClassOutputConnected = isHeadphoneClassOutputConnected
    }

    var withoutRawPortName: HeadphoneAudioRouteSnapshot {
        HeadphoneAudioRouteSnapshot(
            rawPortName: nil,
            rawPortType: rawPortType,
            family: family,
            isHeadphoneClassOutputConnected: isHeadphoneClassOutputConnected
        )
    }

    static let none = HeadphoneAudioRouteSnapshot(
        rawPortName: nil,
        rawPortType: nil,
        family: .none,
        isHeadphoneClassOutputConnected: false
    )
}

enum HeadphoneAudioRouteInspector {
    /// Port types that mean "the climber is wearing or holding a headphone-class device",
    /// as opposed to a speaker, car audio system, or AirPlay receiver. Deliberately excludes
    /// `.airPlay`, which is frequently a speaker rather than headphones.
    private static let headphoneClassPortTypes: Set<AVAudioSession.Port> = [
        .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .headsetMic, .usbAudio
    ]

    static func currentSnapshot(session: AVAudioSession = .sharedInstance()) -> HeadphoneAudioRouteSnapshot {
        guard let output = session.currentRoute.outputs.first(
            where: { headphoneClassPortTypes.contains($0.portType) }
        ) else {
            return .none
        }

        return HeadphoneAudioRouteSnapshot(
            rawPortName: output.portName,
            rawPortType: output.portType.rawValue,
            family: classifyFamily(portName: output.portName),
            isHeadphoneClassOutputConnected: true
        )
    }

    static func classifyFamily(portName: String) -> HeadphoneFamily {
        let name = portName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .unknown }

        let lowercased = name.lowercased()
        if lowercased.contains("airpods pro") { return .airPodsPro }
        if lowercased.contains("airpods max") { return .airPodsMax }
        if lowercased.contains("airpods") { return .airPods }
        if lowercased.contains("beats") { return .beats }
        return .other
    }
}
