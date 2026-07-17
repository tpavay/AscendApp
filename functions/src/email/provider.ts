import {getTransactionalEmailConfig} from "./config";
import type {
  TransactionalEmailDelivery,
  TransactionalEmailMessage,
  TransactionalEmailProvider,
} from "./types";

interface ResendEmailResponse {
  error?: string;
  id?: string;
  message?: string;
}

interface ResendStatusClassification {
  code: string;
  retryable: boolean;
}

/**
 * Wraps provider delivery failures with retry metadata.
 */
export class EmailDeliveryError extends Error {
  code: string;
  provider: TransactionalEmailProvider;
  retryable: boolean;

  /**
   * Creates a stable provider error used by the job processor.
   * @param {string} message - Human-readable error message
   * @param {string} code - Stable error code
   * @param {boolean} retryable - Whether the job should be retried
   * @param {TransactionalEmailProvider} provider - Delivery provider name
   */
  constructor(
    message: string,
    code: string,
    retryable: boolean,
    provider: TransactionalEmailProvider
  ) {
    super(message);
    this.code = code;
    this.provider = provider;
    this.retryable = retryable;
  }
}

/**
 * Formats the sender field expected by Resend.
 * @param {string} fromName - Sender display name
 * @param {string} fromEmail - Sender email
 * @return {string} RFC-friendly sender string
 */
function formatSender(fromName: string, fromEmail: string): string {
  return `${fromName} <${fromEmail}>`;
}

/**
 * Classifies a Resend HTTP status code for retry behavior.
 * @param {number} status - HTTP status code
 * @return {ResendStatusClassification} Retry classification
 */
export function classifyResendStatus(
  status: number
): ResendStatusClassification {
  if (status === 429) {
    return {
      code: "resend_rate_limited",
      retryable: true,
    };
  }

  if (status >= 500) {
    return {
      code: "resend_server_error",
      retryable: true,
    };
  }

  return {
    code: `resend_client_error_${status}`,
    retryable: false,
  };
}

/**
 * Builds the RFC 8058 one-click unsubscribe headers for a message.
 *
 * Both headers must travel together: mailbox providers only treat the list
 * URL as one-click when List-Unsubscribe-Post is present, and without it a
 * POST from Gmail would be indistinguishable from a link prefetch.
 * @param {string | null | undefined} unsubscribeUrl - Signed unsubscribe URL
 * @return {Record<string, string>} Headers to attach to the outgoing message
 */
export function buildUnsubscribeHeaders(
  unsubscribeUrl: string | null | undefined
): Record<string, string> {
  if (!unsubscribeUrl) {
    return {};
  }

  return {
    "List-Unsubscribe": `<${unsubscribeUrl}>`,
    "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
  };
}

/**
 * Safely parses a JSON HTTP response body.
 * @param {Response} response - Fetch response
 * @return {Promise<ResendEmailResponse | null>} Parsed JSON or null
 */
async function parseJsonResponse(
  response: Response
): Promise<ResendEmailResponse | null> {
  try {
    return await response.json() as ResendEmailResponse;
  } catch {
    return null;
  }
}

/**
 * Sends a transactional email through Resend.
 * @param {TransactionalEmailMessage} message - Message payload
 * @return {Promise<TransactionalEmailDelivery>} Delivery result
 */
export async function sendTransactionalEmail(
  message: TransactionalEmailMessage
): Promise<TransactionalEmailDelivery> {
  const config = getTransactionalEmailConfig();

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${config.apiKey}`,
        "Content-Type": "application/json",
        "Idempotency-Key": message.idempotencyKey,
      },
      body: JSON.stringify({
        from: formatSender(config.fromName, config.fromEmail),
        headers: buildUnsubscribeHeaders(message.unsubscribeUrl),
        html: message.html,
        reply_to: message.replyTo ?? config.replyTo,
        subject: message.subject,
        text: message.text,
        to: message.to,
      }),
    });

    const payload = await parseJsonResponse(response);

    if (!response.ok) {
      const classification = classifyResendStatus(response.status);
      const responseMessage = payload?.message ?? payload?.error ??
        `HTTP ${response.status}`;
      throw new EmailDeliveryError(
        `Resend send failed: ${responseMessage}`,
        classification.code,
        classification.retryable,
        "resend"
      );
    }

    if (!payload?.id) {
      throw new EmailDeliveryError(
        "Resend response missing message id",
        "resend_invalid_response",
        false,
        "resend"
      );
    }

    return {
      provider: "resend",
      messageId: payload.id,
    };
  } catch (error) {
    if (error instanceof EmailDeliveryError) {
      throw error;
    }

    throw new EmailDeliveryError(
      "Resend network request failed",
      "resend_network_error",
      true,
      "resend"
    );
  }
}
