import Foundation
import SwiftUI
import Testing
import UIKit
@testable import AscendApp

/// Reviewer-facing evidence for the optional post-climb calibration sheet: it renders its
/// optional, non-rewriting copy, Submit stays disabled until a count is typed, a typed machine
/// count reaches `onSubmit`, and Skip reaches `onSkip`.
@MainActor
@Suite(.serialized, .hostsAWindow)
struct StepAccuracyCalibrationPromptEvidenceTests {
    @Test
    func theSheetOffersSubmitOnlyForATypedCountAndHandsItBack() async throws {
        var submitted: [Int] = []
        var skipCount = 0
        let view = StepAccuracyCalibrationPromptView(
            appSteps: 500,
            onSubmit: { submitted.append($0) },
            onSkip: { skipCount += 1 }
        )

        try await RenderedScreen.host(view) { screen in
            let copy = try await screen.copy()
            #expect(copy.contains("sharpen the count"))
            #expect(copy.contains("500 steps stay exactly as recorded"))
            #expect(copy.contains("raw motion data"))
            #expect(copy.contains("skip"))
            try screen.photograph(named: "step-accuracy-calibration-1-empty")

            // Submit with nothing typed is disabled.
            let submitBeforeTyping = try #require(
                accessibilityElements(under: screen.root).first { $0.accessibilityLabel == "Submit" }
            )
            #expect(submitBeforeTyping.accessibilityTraits.contains(.notEnabled))
            #expect(submitted.isEmpty)

            let field = try #require(Self.textField(in: screen.root))
            // Focus first, as a tap does: SwiftUI applies the field's font to typed text when
            // editing begins, so inserting into an unfocused field draws it in the system face.
            field.becomeFirstResponder()
            field.insertText("605")
            try await screen.settle()
            try screen.photograph(named: "step-accuracy-calibration-2-machine-count-typed")

            try activateAccessibilityElement(labelled: "Submit", in: screen.root)
            try await screen.settle()
            #expect(submitted == [605])

            try activateAccessibilityElement(labelled: "Skip", in: screen.root)
            try await screen.settle()
            #expect(skipCount == 1)
        }
    }

    @Test
    func theCalibratedClimbRecordAndAnalyticsPayloadAreWrittenAsEvidence() throws {
        let route = HeadphoneAudioRouteSnapshot(
            rawPortName: "Tyler's AirPods Pro",
            rawPortType: "BluetoothA2DPOutput",
            family: .airPodsPro,
            isHeadphoneClassOutputConnected: true
        )
        var metadata = HeadphoneMotionWorkoutMetadata(
            sampleCount: 5_400,
            climbId: "empire-state-building",
            targetStepCount: 1_576,
            stopReason: .userStopped,
            headphoneRouteAtStart: route,
            headphoneRouteAtSave: route,
            isMotionCapableHeadphoneConnectedAtStart: true,
            isMotionCapableHeadphoneConnectedAtSave: true,
            didHeadphoneMotionDataFlow: true
        )
        metadata.applyMachineStepCalibration(machineReportedSteps: 605, appSteps: 500)
        let json = try #require(metadata.jsonString)
        #expect(json.count <= 4_000)
        #expect(json.contains("Tyler's AirPods Pro"))

        let recorded = WorkoutStepAccuracyAnalyticsEvent.recorded(
            headphoneFamilyAtStart: .airPodsPro,
            isHeadphoneClassOutputConnectedAtStart: true,
            isMotionCapableHeadphoneConnectedAtStart: true,
            headphoneFamilyAtSave: .airPodsPro,
            isHeadphoneClassOutputConnectedAtSave: true,
            isMotionCapableHeadphoneConnectedAtSave: true,
            didHeadphoneChangeDuringClimb: false,
            didHeadphoneMotionDataFlow: true,
            steps: 500,
            trackingMode: .liveClimb
        ).record
        let submitted = WorkoutStepAccuracyAnalyticsEvent.calibrationSubmitted(
            appSteps: 500,
            machineSteps: 605,
            discrepancyAbs: try #require(metadata.stepDiscrepancyAbs),
            discrepancyPercent: try #require(metadata.stepDiscrepancyPercent)
        ).record
        let analytics = [recorded, submitted].map { record in
            "\(record.name): " + record.parameters.keys.sorted()
                .map { "\($0)=\(record.parameters[$0]!)" }
                .joined(separator: ", ")
        }.joined(separator: "\n")
        #expect(analytics.contains("Tyler") == false)
        #expect(analytics.contains("AirPods Pro") == false)

        guard let directory = ProcessInfo.processInfo.environment["ASCEND_EVIDENCE_DIR"] else { return }
        let text = "Workout.sourceMetadata (\(json.count) chars, owner-private):\n\(json)\n\n" +
            "Analytics events (Mixpanel):\n\(analytics)\n"
        try text.write(
            to: URL(filePath: directory).appending(path: "step-accuracy-record-and-analytics.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func textField(in view: UIView) -> UITextField? {
        if let field = view as? UITextField { return field }
        for subview in view.subviews {
            if let field = textField(in: subview) { return field }
        }
        return nil
    }
}
