// Pure argument normalization shared by every list tool. Kept separate from
// the Firestore calls in index.js so the clamping rules are unit-testable
// without a database.

'use strict';

const DEFAULT_LIMIT = 25;
const MAX_LIMIT = 100;

/**
 * Clamps a caller-supplied limit into [1, MAX_LIMIT], defaulting to
 * DEFAULT_LIMIT when omitted or not a finite number.
 */
function clampLimit(value, { defaultLimit = DEFAULT_LIMIT, maxLimit = MAX_LIMIT } = {}) {
  if (value === undefined || value === null) return defaultLimit;
  const n = Math.trunc(Number(value));
  if (!Number.isFinite(n) || n < 1) return defaultLimit;
  return Math.min(n, maxLimit);
}

module.exports = { DEFAULT_LIMIT, MAX_LIMIT, clampLimit };
