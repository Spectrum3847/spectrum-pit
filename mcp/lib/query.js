// In-memory filter/sort/limit over documents already fetched from Firestore.
//
// index.js pushes at most one equality filter down to Firestore and never
// combines a `.where()` with an `.orderBy()`, so no collection here ever
// needs a composite index. Any remaining filtering, the recency sort, and
// the requested limit happen here instead, on plain JS objects, so this
// whole module is testable without a database.

'use strict';

function toTimeMs(value) {
  const ms = typeof value === 'string' ? Date.parse(value) : NaN;
  return Number.isNaN(ms) ? 0 : ms;
}

function sortByUpdatedAtDesc(docs) {
  return [...docs].sort(
    (a, b) => toTimeMs(b.updatedAt) - toTimeMs(a.updatedAt),
  );
}

/**
 * Filters docs by strict equality on each given field (fields whose filter
 * value is absent are skipped), sorts newest first, and applies the limit.
 */
function selectDocs(docs, filters, limit) {
  let result = docs;
  for (const [field, expected] of Object.entries(filters)) {
    if (expected === undefined || expected === null || expected === '') continue;
    result = result.filter((doc) => doc[field] === expected);
  }
  return sortByUpdatedAtDesc(result).slice(0, limit);
}

const selectInventoryItems = (docs, { status, limit }) =>
  selectDocs(docs, { status }, limit);

const selectPackingRecords = (docs, { packingStatus, limit }) =>
  selectDocs(docs, { packingStatus }, limit);

const selectBorrowRecords = (docs, { returned, limit }) =>
  selectDocs(docs, { returned }, limit);

const selectMapLocations = (docs, { mapType, limit }) =>
  selectDocs(docs, { mapType }, limit);

const selectPitShifts = (docs, { competition, limit }) =>
  selectDocs(docs, { competition }, limit);

/**
 * Groups shifts by competition, for a quick "how much schedule exists where"
 * overview instead of reading every shift individually.
 *
 * @param {object[]} docs - pitShifts documents (each including `id`).
 */
function summarizePitShifts(docs) {
  const byCompetition = new Map();
  for (const doc of docs) {
    const key = typeof doc.competition === 'string' ? doc.competition : '';
    const existing = byCompetition.get(key);
    if (!existing || toTimeMs(doc.updatedAt) > toTimeMs(existing.lastUpdatedAt)) {
      byCompetition.set(key, {
        competition: key,
        shiftCount: (existing?.shiftCount ?? 0) + 1,
        lastUpdatedAt: doc.updatedAt,
      });
    } else {
      existing.shiftCount += 1;
    }
  }
  const competitions = [...byCompetition.values()].sort(
    (a, b) => a.competition.localeCompare(b.competition),
  );
  return {
    totalShifts: docs.length,
    competitionCount: competitions.length,
    competitions,
  };
}

module.exports = {
  selectDocs,
  selectInventoryItems,
  selectPackingRecords,
  selectBorrowRecords,
  selectMapLocations,
  selectPitShifts,
  summarizePitShifts,
};
