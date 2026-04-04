import {onDocumentCreated} from "firebase-functions/v2/firestore";
import * as admin from "firebase-admin";
import {
  getFeedbackNotificationEmail,
  transactionalEmailConfig,
} from "./email/config";
import {sendTransactionalEmail} from "./email/provider";
import {renderFeedbackAdminNotifyEmail} from "./email/templates";
import type {FeedbackAdminNotifyPayload} from "./email/types";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * Validates that a feedback document has the required fields.
 * @param {Record<string, unknown>} data - Raw Firestore document data
 * @param {string} feedbackId - Firestore document ID
 * @return {FeedbackAdminNotifyPayload | null} Validated payload or null
 */
function parseFeedbackDocument(
  data: Record<string, unknown>,
  feedbackId: string
): FeedbackAdminNotifyPayload | null {
  if (
    typeof data.type !== "string" ||
    typeof data.message !== "string" ||
    typeof data.userId !== "string"
  ) {
    return null;
  }

  return {
    appVersion: typeof data.appVersion === "string" ? data.appVersion : "",
    buildNumber: typeof data.buildNumber === "string" ? data.buildNumber : "",
    deviceModel: typeof data.deviceModel === "string" ? data.deviceModel : "",
    feedbackId,
    message: data.message,
    osVersion: typeof data.osVersion === "string" ? data.osVersion : "",
    type: data.type,
    userEmail: typeof data.userEmail === "string" ? data.userEmail : "",
    userId: data.userId,
  };
}

/**
 * Sends an admin notification email when a feedback document is created.
 */
export const onFeedbackCreated = onDocumentCreated(
  {
    document: "feedback/{feedbackId}",
    secrets: [transactionalEmailConfig],
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.error("onFeedbackCreated: no document snapshot");
      return;
    }

    const feedbackId = event.params.feedbackId;
    const data = snapshot.data() as Record<string, unknown>;
    const payload = parseFeedbackDocument(data, feedbackId);

    if (!payload) {
      console.error("onFeedbackCreated: invalid feedback document", {
        feedbackId,
      });
      return;
    }

    const nowTimestamp = admin.firestore.Timestamp.now();
    const feedbackRef = admin.firestore()
      .collection("feedback")
      .doc(feedbackId);

    try {
      const adminEmail = getFeedbackNotificationEmail();
      const rendered = renderFeedbackAdminNotifyEmail(payload);

      const replyTo = payload.userEmail &&
        EMAIL_PATTERN.test(payload.userEmail) ?
        payload.userEmail :
        undefined;

      await sendTransactionalEmail({
        html: rendered.html,
        idempotencyKey: `feedback:${feedbackId}`,
        replyTo,
        subject: rendered.subject,
        text: rendered.text,
        to: [adminEmail],
      });

      await feedbackRef.update({
        adminNotificationErrorCode: null,
        adminNotificationLastAttemptAt: nowTimestamp,
        adminNotificationSentAt: nowTimestamp,
        adminNotificationStatus: "sent",
      });

      console.log("onFeedbackCreated: notification sent", {
        feedbackId,
        type: payload.type,
      });
    } catch (error) {
      const errorCode = error instanceof Error ? error.name : "unknown_error";
      const errorMessage = error instanceof Error ?
        error.message :
        "unknown_error";

      await feedbackRef.update({
        adminNotificationErrorCode: errorCode,
        adminNotificationLastAttemptAt: nowTimestamp,
        adminNotificationSentAt: null,
        adminNotificationStatus: "failed",
      }).catch((updateError) => {
        console.error(
          "onFeedbackCreated: failed to update notification status",
          {feedbackId, updateError}
        );
      });

      console.error("onFeedbackCreated: notification failed", {
        errorCode,
        errorMessage,
        feedbackId,
      });
    }
  }
);
