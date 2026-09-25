import Foundation
import Testing
@testable import AscendApp

struct HeadphoneAudioRouteSnapshotTests {
    @Test
    func classifiesAirPodsProByName() {
        #expect(HeadphoneAudioRouteInspector.classifyFamily(portName: "Tyler's AirPods Pro") == .airPodsPro)
    }

    @Test
    func classifiesAirPodsMaxByName() {
        #expect(HeadphoneAudioRouteInspector.classifyFamily(portName: "AirPods Max") == .airPodsMax)
    }

    @Test
    func classifiesPlainAirPodsByName() {
        #expect(HeadphoneAudioRouteInspector.classifyFamily(portName: "AirPods") == .airPods)
    }

    @Test
    func prefersProOverPlainAirPodsWhenBothSubstringsMatch() {
        #expect(HeadphoneAudioRouteInspector.classifyFamily(portName: "AirPods Pro 2") == .airPodsPro)
    }

    @Test
    func classifiesBeatsByName() {
        #expect(HeadphoneAudioRouteInspector.classifyFamily(portName: "Beats Fit Pro") == .beats)
    }

    @Test
    func classifiesThirdPartyNameAsOther() {
        #expect(HeadphoneAudioRouteInspector.classifyFamily(portName: "Sony WH-1000XM5") == .other)
    }

    @Test
    func classifiesBlankNameAsUnknown() {
        #expect(HeadphoneAudioRouteInspector.classifyFamily(portName: "   ") == .unknown)
    }

    @Test
    func noneSnapshotReportsNoHeadphoneClassOutput() {
        #expect(HeadphoneAudioRouteSnapshot.none.isHeadphoneClassOutputConnected == false)
        #expect(HeadphoneAudioRouteSnapshot.none.family == .none)
        #expect(HeadphoneAudioRouteSnapshot.none.rawPortName == nil)
    }
}
