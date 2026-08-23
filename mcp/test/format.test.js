'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  truncate,
  formatInventoryItemSummary,
  formatInventoryItemDetail,
  formatPackingRecordSummary,
  formatPackingRecordDetail,
  formatBorrowRecordSummary,
  formatBorrowRecordDetail,
  formatMapLocationSummary,
  formatMapLocationDetail,
  formatPitShiftSummary,
  formatPitShiftDetail,
} = require('../lib/format');

test('truncate passes short text through unchanged', () => {
  assert.equal(truncate('hello', 10), 'hello');
});

test('truncate cuts long text and appends an ellipsis', () => {
  assert.equal(truncate('a'.repeat(250), 240), `${'a'.repeat(240)}...`);
});

test('truncate handles missing or non-string input', () => {
  assert.equal(truncate(undefined, 10), '');
  assert.equal(truncate(null, 10), '');
});

test('formatInventoryItemSummary keeps locations but omits mapRef', () => {
  const doc = {
    id: 'i1',
    name: 'DeWalt Drill Kit',
    labLocation: 'Cabinet A, Shelf 2',
    pitLocation: 'Road Case 1, Drawer B',
    mapRef: 'loc123',
    status: 'inPit',
    updatedAt: '2026-08-01T00:00:00.000Z',
  };
  const summary = formatInventoryItemSummary(doc);
  assert.equal(summary.name, 'DeWalt Drill Kit');
  assert.equal(summary.status, 'inPit');
  assert.equal(summary.pitLocation, 'Road Case 1, Drawer B');
  assert.equal('mapRef' in summary, false);
});

test('formatInventoryItemDetail includes the map reference when present', () => {
  const detail = formatInventoryItemDetail({
    id: 'i1',
    name: 'Drill',
    status: 'inLab',
    mapRef: 'loc123',
  });
  assert.equal(detail.mapRef, 'loc123');
  assert.equal(formatInventoryItemDetail({ id: 'i1' }).mapRef, null);
});

test('formatPackingRecordSummary reports photo presence without the key', () => {
  const summary = formatPackingRecordSummary({
    id: 'p1',
    itemId: 'i1',
    packingStatus: 'loading',
    photoRef: 'packing/p1.jpg',
    updatedAt: '2026-08-01T00:00:00.000Z',
  });
  assert.equal(summary.hasPhoto, true);
  assert.equal('photoRef' in summary, false);
});

test('formatPackingRecordSummary reports no photo when absent', () => {
  assert.equal(formatPackingRecordSummary({ id: 'p1' }).hasPhoto, false);
});

test('formatPackingRecordDetail passes through the photo key', () => {
  const detail = formatPackingRecordDetail({
    id: 'p1',
    itemId: 'i1',
    packingStatus: 'ready',
    photoRef: 'packing/p1.jpg',
  });
  assert.equal(detail.photoRef, 'packing/p1.jpg');
  assert.equal(formatPackingRecordDetail({ id: 'p1' }).photoRef, null);
});

test('formatBorrowRecordSummary keeps loan state and drops contact details', () => {
  const summary = formatBorrowRecordSummary({
    id: 'b1',
    toolName: 'Hex driver set',
    teamName: 'Team 254',
    teamNumber: 254,
    competition: 'Week 0',
    contact: 'someone@example.com',
    checkedOutAt: '2026-08-01T14:00:00.000Z',
    estimatedReturn: '2026-08-02T12:00:00.000Z',
    checkedInAt: null,
    returned: false,
    updatedAt: '2026-08-01T14:00:00.000Z',
  });
  assert.equal(summary.toolName, 'Hex driver set');
  assert.equal(summary.returned, false);
  assert.equal(summary.estimatedReturn, '2026-08-02T12:00:00.000Z');
  assert.equal('contact' in summary, false);
  assert.equal('checkedInAt' in summary, false);
});

test('formatBorrowRecordDetail defaults missing optional fields', () => {
  const detail = formatBorrowRecordDetail({ id: 'b1', toolName: 'Wrench' });
  assert.equal(detail.itemId, null);
  assert.equal(detail.contact, null);
  assert.equal(detail.estimatedReturn, null);
  assert.equal(detail.checkedInAt, null);
  assert.equal(detail.returned, false);
});

test('formatMapLocationSummary keeps only the pin name and type', () => {
  const summary = formatMapLocationSummary({
    id: 'm1',
    name: 'Lathe bench',
    mapType: 'lab',
    x: 0.42,
    y: 0.61,
    updatedAt: '2026-08-01T00:00:00.000Z',
  });
  assert.equal(summary.name, 'Lathe bench');
  assert.equal(summary.mapType, 'lab');
  assert.equal('x' in summary, false);
});

test('formatMapLocationDetail includes normalized coordinates', () => {
  const detail = formatMapLocationDetail({
    id: 'm1',
    name: 'Lathe bench',
    mapType: 'lab',
    x: 0.42,
    y: 0.61,
    inventoryItemId: 'i1',
  });
  assert.equal(detail.x, 0.42);
  assert.equal(detail.y, 0.61);
  assert.equal(detail.inventoryItemId, 'i1');
  assert.equal(formatMapLocationDetail({ id: 'm1' }).inventoryItemId, null);
});

test('formatPitShiftSummary counts assignees without listing them and truncates notes', () => {
  const summary = formatPitShiftSummary({
    id: 's1',
    label: 'Load-in crew',
    kind: 'loadIn',
    competition: 'Week 0',
    assignedNames: ['Alice', 'Bob'],
    startMatch: 1,
    endMatch: 3,
    notes: 'n'.repeat(300),
    updatedAt: '2026-08-01T00:00:00.000Z',
  });
  assert.equal(summary.assigneeCount, 2);
  assert.equal('assignedNames' in summary, false);
  assert.equal(summary.startMatch, 1);
  assert.equal(summary.notesPreview.length, 243); // 240 chars + "..."
});

test('formatPitShiftSummary defaults a wall-clock shift to null match bounds', () => {
  const summary = formatPitShiftSummary({
    id: 's2',
    kind: 'matchBlock',
    startsAt: '2026-08-01T09:00:00.000Z',
    endsAt: '2026-08-01T11:00:00.000Z',
  });
  assert.equal(summary.startMatch, null);
  assert.equal(summary.startsAt, '2026-08-01T09:00:00.000Z');
});

test('formatPitShiftDetail includes assignees, notes, and import origin', () => {
  const detail = formatPitShiftDetail({
    id: 's1',
    label: 'Match block',
    kind: 'matchBlock',
    competition: 'Week 0',
    assignedUids: ['uid1', 'unlinked:carl'],
    assignedNames: ['Alice', 'Carl'],
    notes: 'bring carts',
    importedFrom: 'driver-schedule',
  });
  assert.deepEqual(detail.assignedUids, ['uid1', 'unlinked:carl']);
  assert.deepEqual(detail.assignedNames, ['Alice', 'Carl']);
  assert.equal(detail.notes, 'bring carts');
  assert.equal(detail.importedFrom, 'driver-schedule');
});

test('formatPitShiftDetail defaults a hand-made shift', () => {
  const detail = formatPitShiftDetail({ id: 's1', kind: 'pitDuty' });
  assert.deepEqual(detail.assignedUids, []);
  assert.deepEqual(detail.assignedNames, []);
  assert.equal(detail.notes, null);
  assert.equal(detail.importedFrom, null);
});
