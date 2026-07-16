import {createHash} from "crypto";

/**
 * Normalizes an email for deduplication comparisons.
 * @param {string} value - Raw email input
 * @return {string} Trimmed lowercase email
 */
export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

/**
 * Creates a stable SHA-256 hash for a string value.
 * @param {string} value - Raw string value
 * @return {string} Hex-encoded hash
 */
export function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
