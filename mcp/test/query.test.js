'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  selectInventoryItems,
  selectPackingRecords,
  selectBorrowRecords,
  selectMapLocations,
  selectPitShifts,
  summarizePitShifts,
} = require('../lib/query');

const INVENTORY_ITEMS = [
  { id: 'a', name: 'Drill', status: 'inLab', updatedAt: '2026-08-01T00:00:00.000Z' },
  { id: 'b', name: 'Wrench set', status: 'inPit', updatedAt: '2026-08-03T00:00:00.000Z' },
  { id: 'c', name: 'Hex drivers', status: 'borrowed', updatedAt: '2026-08-02T00:00:00.000Z' },
  { id: 'd', name: 'Bench vise', status: 'inLab', updatedAt: '2026-08-04T00:00:00.000Z' },
];

test('selectInventoryItems filters by status, newest first', () => {
  const result = selectInventoryItems(INVENTORY_ITEMS, { status: 'inLab', limit: 10 });
  assert.deepEqual(
    result.map((d) => d.id),
    ['d', 'a'],
  );
});

test('selectInventoryItems sorts newest first and respects the limit with no filter', () => {
  const result = selectInventoryItems(INVENTORY_ITEMS, { limit: 2 });
  assert.deepEqual(
    result.map((d) => d.id),
    ['d', 'b'],
  );
});

test('selectInventoryItems treats an unparseable updatedAt as oldest', () => {
  const docs = [
    { id: 'bad', status: 'inLab', updatedAt: 'not-a-date' },
    { id: 'good', status: 'inLab', updatedAt: '2026-08-01T00:00:00.000Z' },
  ];
  const result = selectInventoryItems(docs, { status: 'inLab', limit: 10 });
  assert.deepEqual(
    result.map((d) => d.id),
    ['good', 'bad'],
  );
});

const PACKING_RECORDS = [
  { id: 'r1', itemId: 'i1', packingStatus: 'packing', updatedAt: '2026-08-01T00:00:00.000Z' },
  { id: 'r2', itemId: 'i2', packingStatus: 'staging', updatedAt: '2026-08-02T00:00:00.000Z' },
  { id: 'r3', itemId: 'i3', packingStatus: 'ready', updatedAt: '2026-08-03T00:00:00.000Z' },
  { id: 'r4', itemId: 'i4', packingStatus: 'loading', updatedAt: '2026-08-04T00:00:00.000Z' },
];

test('selectPackingRecords filters by packingStatus', () => {
  const result = selectPackingRecords(PACKING_RECORDS, { packingStatus: 'staging', limit: 10 });
  assert.deepEqual(
    result.map((d) => d.id),
    ['r2'],
  );
});

const BORROW_RECORDS = [
  { id: 'o1', toolName: 'Drill', returned: false, updatedAt: '2026-08-01T00:00:00.000Z' },
  { id: 'o2', toolName: 'Saw', returned: true, updatedAt: '2026-08-02T00:00:00.000Z' },
  { id: 'o3', toolName: 'Clamp', returned: false, updatedAt: '2026-08-03T00:00:00.000Z' },
];

test('selectBorrowRecords filters outstanding loans by returned=false', () => {
  const result = selectBorrowRecords(BORROW_RECORDS, { returned: false, limit: 10 });
  assert.deepEqual(
    result.map((d) => d.id),
    ['o3', 'o1'],
  );
});

test('selectBorrowRecords filters returned loans by returned=true', () => {
  const result = selectBorrowRecords(BORROW_RECORDS, { returned: true, limit: 10 });
  assert.deepEqual(
    result.map((d) => d.id),
    ['o2'],
  );
});

const MAP_LOCATIONS = [
  { id: 'm1', name: 'Lathe bench', mapType: 'lab', updatedAt: '2026-08-01T00:00:00.000Z' },
  { id: 'm2', name: 'Cart 3', mapType: 'pit', updatedAt: '2026-08-02T00:00:00.000Z' },
  { id: 'm3', name: 'Trailer ramp', mapType: 'vehicle', updatedAt: '2026-08-03T00:00:00.000Z' },
];

test('selectMapLocations filters by mapType', () => {
  const result = selectMapLocations(MAP_LOCATIONS, { mapType: 'lab', limit: 10 });
  assert.deepEqual(
    result.map((d) => d.id),
    ['m1'],
  );
});

const PIT_SHIFTS = [
  { id: 's1', competition: 'Week 0', kind: 'loadIn', updatedAt: '2026-08-01T00:00:00.000Z' },
  { id: 's2', competition: 'Week 0', kind: 'matchBlock', updatedAt: '2026-08-02T00:00:00.000Z' },
  { id: 's3', competition: 'District Champs', kind: 'loadOut', updatedAt: '2026-08-03T00:00:00.000Z' },
  { id: 's4', competition: 'Week 0', kind: 'unavailable', updatedAt: '2026-07-30T00:00:00.000Z' },
];

test('selectPitShifts filters by competition, newest first', () => {
  const result = selectPitShifts(PIT_SHIFTS, { competition: 'Week 0', limit: 10 });
  assert.deepEqual(
    result.map((d) => d.id),
    ['s2', 's1', 's4'],
  );
});

test('selectPitShifts respects the limit after sorting', () => {
  const result = selectPitShifts(PIT_SHIFTS, { competition: 'Week 0', limit: 1 });
  assert.deepEqual(result.map((d) => d.id), ['s2']);
});

test('summarizePitShifts counts shifts per competition and finds the latest update', () => {
  const summary = summarizePitShifts(PIT_SHIFTS);
  assert.equal(summary.totalShifts, 4);
  assert.equal(summary.competitionCount, 2);
  assert.deepEqual(summary.competitions, [
    { competition: 'District Champs', shiftCount: 1, lastUpdatedAt: '2026-08-03T00:00:00.000Z' },
    { competition: 'Week 0', shiftCount: 3, lastUpdatedAt: '2026-08-02T00:00:00.000Z' },
  ]);
});

test('summarizePitShifts groups shifts missing a competition under an empty label', () => {
  const docs = [
    { id: 's1', competition: '', updatedAt: '2026-08-01T00:00:00.000Z' },
    { id: 's2', updatedAt: '2026-08-02T00:00:00.000Z' },
  ];
  const summary = summarizePitShifts(docs);
  assert.equal(summary.totalShifts, 2);
  assert.equal(summary.competitionCount, 1);
  assert.equal(summary.competitions[0].competition, '');
  assert.equal(summary.competitions[0].shiftCount, 2);
  assert.equal(summary.competitions[0].lastUpdatedAt, '2026-08-02T00:00:00.000Z');
});

test('summarizePitShifts handles an empty schedule', () => {
  const summary = summarizePitShifts([]);
  assert.equal(summary.totalShifts, 0);
  assert.equal(summary.competitionCount, 0);
  assert.deepEqual(summary.competitions, []);
});
