import FirebaseFirestore
import Testing
@testable import AscendApp

struct ModerationRepositoryPayloadTests {
    @Test
    func blockPayloadHasExactSchemaAndTarget() {
        let payload = ModerationRepository.blockPayload(
            blockedUserId: "blocked-user"
        )

        #expect(Set(payload.keys) == ["blockedUid", "createdAt"])
        #expect(payload["blockedUid"] as? String == "blocked-user")
        #expect(payload["createdAt"] is FieldValue)
    }

    @Test
    func reportPayloadHasExactActionableTupleAndSchema() {
        let payload = ModerationRepository.reportPayload(
            reporterUserId: "reporter",
            reportedUserId: "reported",
            reason: .inappropriatePhoto,
            source: .communityAvatars
        )

        #expect(
            Set(payload.keys) == [
                "reportedUserId",
                "reporterUserId",
                "reason",
                "source",
                "createdAt"
            ]
        )
        #expect(payload["reporterUserId"] as? String == "reporter")
        #expect(payload["reportedUserId"] as? String == "reported")
        #expect(payload["reason"] as? String == "inappropriate_photo")
        #expect(payload["source"] as? String == "community_avatars")
        #expect(payload["createdAt"] is FieldValue)
    }

    @Test
    func reportRateLimitPayloadBindsTheTimestampToOneReportDocument() {
        let payload = ModerationRepository.reportRateLimitPayload(
            reportId: "report-123"
        )

        #expect(
            Set(payload.keys) == [
                "lastModerationReport",
                "lastModerationReportId"
            ]
        )
        #expect(payload["lastModerationReport"] is FieldValue)
        #expect(payload["lastModerationReportId"] as? String == "report-123")
    }
}
