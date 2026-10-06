import FirebaseFirestore
import Foundation
import Testing
@testable import AscendApp

/// Which class each failure lands in. Every row here used to be the single `other` bucket, which
/// is why a rules outage and a dropped stream showed the climber the same sentence.
struct ServerReadFailureClassTests {
    @Test(arguments: [
        FirestoreErrorCode.unavailable,
        .deadlineExceeded,
        .cancelled,
        .internal
    ])
    func firestoreCodesThatMeanNoServerAnswerAreUnreachable(code: FirestoreErrorCode.Code) {
        #expect(ServerReadFailureClass.classify(Firestore.error(code)) == .unreachable)
    }

    @Test(arguments: [FirestoreErrorCode.permissionDenied, .unauthenticated])
    func firestoreCodesThatMeanTheServerSaidNoAreRefused(code: FirestoreErrorCode.Code) {
        #expect(ServerReadFailureClass.classify(Firestore.error(code)) == .refused)
    }

    /// A missing index is `failedPrecondition`: a defect, not a connection.
    @Test(arguments: [
        FirestoreErrorCode.failedPrecondition,
        .resourceExhausted,
        .invalidArgument,
        .notFound,
        .unknown,
        .dataLoss
    ])
    func everyOtherFirestoreCodeIsUnexpected(code: FirestoreErrorCode.Code) {
        #expect(ServerReadFailureClass.classify(Firestore.error(code)) == .unexpected)
    }

    @Test
    func transportFailuresTimeoutsAndCancellationAreUnreachable() {
        #expect(ServerReadFailureClass.classify(URLError(.networkConnectionLost)) == .unreachable)
        #expect(ServerReadFailureClass.classify(URLError(.timedOut)) == .unreachable)
        #expect(ServerReadFailureClass.classify(LeaderboardTimeoutError.operationTimedOut) == .unreachable)
        #expect(ServerReadFailureClass.classify(CancellationError()) == .unreachable)
    }

    @Test
    func anErrorNobodyClassifiedIsUnexpected() {
        struct Unclassified: Error {}
        #expect(ServerReadFailureClass.classify(Unclassified()) == .unexpected)
    }
}
