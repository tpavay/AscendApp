import CryptoKit
import Foundation
import MetricKit

/// One `MXCrashDiagnostic`, reduced to the facts Ascend records about a crash of its own.
///
/// iOS writes the diagnostic into system-reserved space from the same data as its own `.ips`
/// report and hands it to the app on the next launch, so it survives the one failure mode that
/// silences both in-process crash reporters: a volume with no free blocks, where neither SDK can
/// create its report file at crash time. Sentry's own MetricKit integration (9.18) converts the
/// call-stack tree but not `exceptionReason`, and that is the one string that names the failing
/// assertion and its `errno` - which is why Ascend records it itself.
///
/// A value type on purpose: `MXCrashDiagnostic` cannot be constructed in a test, so the mapping
/// from it is one thin initialiser and everything downstream - the record, the message, the
/// fingerprint - is exercised on a summary a test builds directly.
struct AppCrashDiagnosticSummary: Equatable, Sendable {
    /// `MXCrashDiagnosticObjectiveCExceptionReason` (iOS 17+): the NSException that ended the
    /// process, when the crash was one. `composedMessage` is the formatted reason - for the
    /// LevelDB assertion, the text that carries the operation and the `errno`.
    struct ExceptionReason: Equatable, Sendable {
        var exceptionName: String
        var className: String
        var composedMessage: String
    }

    /// How much of the composed message an analytics parameter carries. Firebase Analytics drops
    /// a parameter value longer than 100 characters, so the full text travels to Sentry instead.
    static let analyticsMessageLimit = 100
    /// How much of the composed message the Sentry message event carries; the SDK's own ceiling
    /// is 8 KiB, and nothing an assertion prints needs half of that.
    static let messageEventLimit = 4_000

    var appBuildVersion: String
    var osVersion: String
    var deviceType: String
    /// The diagnostic payload's time range: when the crash it describes was collected.
    var periodStart: Date
    var periodEnd: Date
    /// Mach exception type, Mach exception code and BSD signal, as iOS reported them.
    var exceptionType: Int?
    var exceptionCode: Int?
    var signal: Int?
    var terminationReason: String?
    /// Whether iOS attached a virtual memory region description, which it does for a bad access
    /// and never for an abort. Presence only: the text itself is addresses.
    var hasVirtualMemoryRegionInfo: Bool
    var exceptionReason: ExceptionReason?
    /// SHA-256 of the call-stack tree's JSON, so two diagnostics of the same signal that died in
    /// different places stay distinct without carrying the tree itself.
    var callStackDigest: String

    /// The identity a redelivered diagnostic shares with its first delivery and nothing else
    /// does. MetricKit hands a payload over once, but a payload the app did not finish handling
    /// comes back, and `MXMetricManager.pastDiagnosticPayloads` can replay it; one report per
    /// crash is the contract.
    var fingerprint: String {
        let fields: [String] = [
            appBuildVersion,
            osVersion,
            String(Int(periodStart.timeIntervalSince1970)),
            String(Int(periodEnd.timeIntervalSince1970)),
            exceptionType.map(String.init) ?? "",
            exceptionCode.map(String.init) ?? "",
            signal.map(String.init) ?? "",
            terminationReason ?? "",
            exceptionReason?.exceptionName ?? "",
            exceptionReason?.composedMessage ?? "",
            callStackDigest
        ]
        return Self.sha256Hex(fields.joined(separator: "\u{1F}"))
    }

    /// The analytics record: one `app_crash_diagnostic` event per crash the system reported.
    var record: TelemetryRecord {
        var parameters: [String: TelemetryValue] = [
            "app_build_version": .string(appBuildVersion),
            "os_version": .string(osVersion),
            "device_type": .string(deviceType),
            "period_start_unix": .int(Int(periodStart.timeIntervalSince1970)),
            "period_end_unix": .int(Int(periodEnd.timeIntervalSince1970)),
            "has_virtual_memory_region_info": .bool(hasVirtualMemoryRegionInfo),
            "has_exception_reason": .bool(exceptionReason != nil),
            "fingerprint": .string(fingerprint)
        ]
        if let exceptionType {
            parameters["exception_type"] = .int(exceptionType)
        }
        if let exceptionCode {
            parameters["exception_code"] = .int(exceptionCode)
        }
        if let signal {
            parameters["signal"] = .int(signal)
        }
        if let terminationReason {
            parameters["termination_reason"] = .string(String(terminationReason.prefix(Self.analyticsMessageLimit)))
        }
        if let exceptionReason {
            parameters["exception_name"] = .string(exceptionReason.exceptionName)
            parameters["exception_class"] = .string(exceptionReason.className)
            parameters["exception_message"] = .string(String(exceptionReason.composedMessage.prefix(Self.analyticsMessageLimit)))
        }
        return TelemetryRecord(name: "app_crash_diagnostic", parameters: parameters)
    }

    /// The same facts as flat strings, for the diagnostics ring buffer and the Sentry breadcrumb
    /// it becomes. `AppDiagnosticsRecorder` bounds each value itself.
    var diagnosticDetails: [String: String] {
        var details: [String: String] = [
            "app_build_version": appBuildVersion,
            "os_version": osVersion,
            "device_type": deviceType,
            "period_start_unix": String(Int(periodStart.timeIntervalSince1970)),
            "period_end_unix": String(Int(periodEnd.timeIntervalSince1970)),
            "has_virtual_memory_region_info": hasVirtualMemoryRegionInfo ? "true" : "false",
            "fingerprint": fingerprint
        ]
        if let exceptionType {
            details["exception_type"] = String(exceptionType)
        }
        if let exceptionCode {
            details["exception_code"] = String(exceptionCode)
        }
        if let signal {
            details["signal"] = String(signal)
        }
        if let terminationReason {
            details["termination_reason"] = terminationReason
        }
        if let exceptionReason {
            details["exception_name"] = exceptionReason.exceptionName
            details["exception_class"] = exceptionReason.className
            details["exception_message"] = exceptionReason.composedMessage
        }
        return details
    }

    /// The text of the Sentry message event: the one place the full assertion string is
    /// searchable, since the SDK's own conversion of the same diagnostic omits it.
    var messageEventText: String {
        var line = "MetricKit crash diagnostic"
        if let exceptionReason {
            line += ": \(exceptionReason.exceptionName): \(String(exceptionReason.composedMessage.prefix(Self.messageEventLimit)))"
        } else if let signal {
            line += ": signal \(signal)"
            if let terminationReason {
                line += " (\(String(terminationReason.prefix(Self.messageEventLimit))))"
            }
        } else if let terminationReason {
            line += ": \(String(terminationReason.prefix(Self.messageEventLimit)))"
        }
        return line
    }

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

extension AppCrashDiagnosticSummary {
    /// The one place a live `MXCrashDiagnostic` is read. Untestable in a simulator, so it does
    /// nothing but copy fields.
    init(diagnostic: MXCrashDiagnostic, payload: MXDiagnosticPayload) {
        self.init(
            appBuildVersion: diagnostic.metaData.applicationBuildVersion,
            osVersion: diagnostic.metaData.osVersion,
            deviceType: diagnostic.metaData.deviceType,
            periodStart: payload.timeStampBegin,
            periodEnd: payload.timeStampEnd,
            exceptionType: diagnostic.exceptionType?.intValue,
            exceptionCode: diagnostic.exceptionCode?.intValue,
            signal: diagnostic.signal?.intValue,
            terminationReason: diagnostic.terminationReason,
            hasVirtualMemoryRegionInfo: diagnostic.virtualMemoryRegionInfo != nil,
            exceptionReason: diagnostic.exceptionReason.map {
                ExceptionReason(
                    exceptionName: $0.exceptionName,
                    className: $0.className,
                    composedMessage: $0.composedMessage
                )
            },
            callStackDigest: Self.sha256Hex(
                String(decoding: diagnostic.callStackTree.jsonRepresentation(), as: UTF8.self)
            )
        )
    }
}
