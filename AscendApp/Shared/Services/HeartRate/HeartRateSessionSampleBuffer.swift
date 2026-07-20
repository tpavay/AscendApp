import Foundation

/// Accumulates a live session's heart-rate trace and carries its own persisted
/// JSON representation.
///
/// The draft checkpoint runs every couple of seconds for an hour or more, so the
/// payload is assembled incrementally: each sample is encoded once, on append,
/// and `encodedPayload` only wraps the already-encoded elements in array
/// brackets. Re-encoding the whole growing series on every checkpoint would be
/// quadratic work on the main actor during a workout.
struct HeartRateSessionSampleBuffer: Equatable, Sendable {
    private static let elementSeparator = Data(",".utf8)
    private static let arrayOpen = Data("[".utf8)
    private static let arrayClose = Data("]".utf8)

    private(set) var samples: [HeartRateDataPoint]
    private let minimumCaptureInterval: TimeInterval
    private var lastCaptureAt: Date?
    private var encodedElements: Data

    init(
        restoring samples: [HeartRateDataPoint] = [],
        minimumCaptureInterval: TimeInterval = 0.9
    ) {
        self.samples = []
        self.minimumCaptureInterval = minimumCaptureInterval
        self.lastCaptureAt = nil
        self.encodedElements = Data()

        for sample in samples.filter({ $0.heartRate > 0 }).sorted(by: { $0.timestamp < $1.timestamp }) {
            append(sample)
        }
    }

    /// The full series as a JSON array, byte-identical to encoding `samples`
    /// directly. Nil when the session captured nothing.
    var encodedPayload: Data? {
        guard !encodedElements.isEmpty else { return nil }

        var payload = Data(capacity: encodedElements.count + 2)
        payload.append(Self.arrayOpen)
        payload.append(encodedElements)
        payload.append(Self.arrayClose)
        return payload
    }

    mutating func record(
        beatsPerMinute: Int,
        capturedAt: Date,
        sessionStartedAt: Date,
        sessionElapsed: TimeInterval
    ) {
        guard beatsPerMinute > 0 else { return }
        if let lastCaptureAt,
           capturedAt.timeIntervalSince(lastCaptureAt) < minimumCaptureInterval {
            return
        }

        lastCaptureAt = capturedAt
        let sample = HeartRateDataPoint(
            timestamp: sessionStartedAt.addingTimeInterval(max(sessionElapsed, 0)),
            heartRate: beatsPerMinute
        )

        if let lastSample = samples.last,
           sample.timestamp <= lastSample.timestamp {
            return
        }

        append(sample)
    }

    /// The only mutator of both the series and its encoding, so a sample that
    /// fails to encode never lands in `samples` and the two cannot diverge.
    private mutating func append(_ sample: HeartRateDataPoint) {
        guard let element = try? JSONEncoder().encode(sample) else { return }

        if !encodedElements.isEmpty {
            encodedElements.append(Self.elementSeparator)
        }
        encodedElements.append(element)
        samples.append(sample)
    }
}
