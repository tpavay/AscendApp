/**
 * Deterministic hashing and pseudo-random helpers shared by seed scripts.
 *
 * Seed fixtures must be reproducible: re-running a seed with the same seed pack
 * has to produce the same synthetic climbers, curves, and dates so repeated
 * seeds merge onto identical documents instead of rewriting fixture history.
 */

/**
 * FNV-1a hash of a string, as an unsigned 32-bit integer.
 * @param {string} value Value to hash.
 * @return {number} Unsigned 32-bit hash.
 */
export function hashString(value) {
  let hash = 2166136261;
  for (let index = 0; index < value.length; index += 1) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

/**
 * Builds a mulberry32 pseudo-random generator for a numeric seed.
 * @param {number} seed Numeric seed.
 * @return {() => number} Generator returning values in [0, 1).
 */
export function mulberry32(seed) {
  return function random() {
    let value = seed += 0x6D2B79F5;
    value = Math.imul(value ^ value >>> 15, value | 1);
    value ^= value + Math.imul(value ^ value >>> 7, value | 61);
    return ((value ^ value >>> 14) >>> 0) / 4294967296;
  };
}
