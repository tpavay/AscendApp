import Foundation
import Testing
@testable import AscendApp

struct LifecycleEmailConsentTests {
    @Test
    func anAbsentFlagIsNotConsent() {
        // The whole point of the screen: Ascend used to read silence as a yes,
        // so it could not name one climber who had actually chosen to hear
        // from it. Nothing may be sent on the strength of an unanswered
        // question.
        let consent = LifecycleEmailConsent(storedFlag: nil)

        #expect(consent == .undecided)
        #expect(consent.allowsEmail == false)
        #expect(consent.isDecided == false)
    }

    @Test
    func aStoredYesAllowsEmail() {
        let consent = LifecycleEmailConsent(storedFlag: true)

        #expect(consent == .granted)
        #expect(consent.allowsEmail)
        #expect(consent.isDecided)
    }

    @Test
    func aStoredNoIsADecisionAndBlocksEmail() {
        // A no and a never-answered both stop mail, but only one of them is a
        // recorded answer, and the difference is what the record is for.
        let consent = LifecycleEmailConsent(storedFlag: false)

        #expect(consent == .declined)
        #expect(consent.allowsEmail == false)
        #expect(consent.isDecided)
    }

    @Test
    func aFreshAnswerIsAlwaysDecided() {
        #expect(LifecycleEmailConsent(isGranted: true) == .granted)
        #expect(LifecycleEmailConsent(isGranted: false) == .declined)
    }

    @Test
    func onlyGrantedAllowsEmail() {
        let allowed = LifecycleEmailConsent.allCases.filter(\.allowsEmail)

        #expect(allowed == [.granted])
    }
}
