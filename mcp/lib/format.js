// Shapes raw Firestore documents into the compact objects this server
// returns from its tools. Kept separate from the Firestore calls so the
// formatting rules are unit-testable without a database.

'use strict';

const NOTES_PREVIEW_LENGTH = 240;

function truncate(text, maxLength) {
  if (typeof text !== 'string' || text.length <= maxLength) return text ?? '';
  return `${text.slice(0, maxLength)}...`;
}

function formatInventoryItemSummary(doc) {
  return {
    id: doc.id,
    name: doc.name || '',
    status: doc.status || '',
    labLocation: doc.labLocation || '',
    pitLocation: doc.pitLocation || '',
    updatedAt: doc.updatedAt,
  };
}

function formatInventoryItemDetail(doc) {
  return {
    id: doc.id,
    name: doc.name || '',
    status: doc.status || '',
    labLocation: doc.labLocation || '',
    pitLocation: doc.pitLocation || '',
    mapRef: doc.mapRef ?? null,
    updatedAt: doc.updatedAt,
  };
}

function formatPackingRecordSummary(doc) {
  return {
    id: doc.id,
    itemId: doc.itemId || '',
    packingStatus: doc.packingStatus || '',
    hasPhoto: Boolean(doc.photoRef),
    updatedAt: doc.updatedAt,
  };
}

function formatPackingRecordDetail(doc) {
  return {
    id: doc.id,
    itemId: doc.itemId || '',
    packingStatus: doc.packingStatus || '',
    photoRef: doc.photoRef ?? null,
    updatedAt: doc.updatedAt,
  };
}

function formatBorrowRecordSummary(doc) {
  return {
    id: doc.id,
    toolName: doc.toolName || '',
    teamName: doc.teamName || '',
    teamNumber: doc.teamNumber,
    competition: doc.competition || '',
    returned: Boolean(doc.returned),
    checkedOutAt: doc.checkedOutAt,
    estimatedReturn: doc.estimatedReturn ?? null,
    updatedAt: doc.updatedAt,
  };
}

function formatBorrowRecordDetail(doc) {
  return {
    id: doc.id,
    itemId: doc.itemId ?? null,
    toolName: doc.toolName || '',
    teamName: doc.teamName || '',
    teamNumber: doc.teamNumber,
    competition: doc.competition || '',
    contact: doc.contact ?? null,
    checkedOutAt: doc.checkedOutAt,
    estimatedReturn: doc.estimatedReturn ?? null,
    checkedInAt: doc.checkedInAt ?? null,
    returned: Boolean(doc.returned),
    updatedAt: doc.updatedAt,
  };
}

function formatMapLocationSummary(doc) {
  return {
    id: doc.id,
    name: doc.name || '',
    mapType: doc.mapType || '',
    updatedAt: doc.updatedAt,
  };
}

function formatMapLocationDetail(doc) {
  return {
    id: doc.id,
    name: doc.name || '',
    mapType: doc.mapType || '',
    x: typeof doc.x === 'number' ? doc.x : null,
    y: typeof doc.y === 'number' ? doc.y : null,
    inventoryItemId: doc.inventoryItemId ?? null,
    updatedAt: doc.updatedAt,
  };
}

function formatPitShiftSummary(doc) {
  const assignees = Array.isArray(doc.assignedNames) ? doc.assignedNames : [];
  return {
    id: doc.id,
    label: doc.label || '',
    kind: doc.kind || '',
    competition: doc.competition || '',
    assigneeCount: assignees.length,
    startMatch: typeof doc.startMatch === 'number' ? doc.startMatch : null,
    endMatch: typeof doc.endMatch === 'number' ? doc.endMatch : null,
    startsAt: doc.startsAt ?? null,
    endsAt: doc.endsAt ?? null,
    notesPreview: truncate(doc.notes, NOTES_PREVIEW_LENGTH),
    updatedAt: doc.updatedAt,
  };
}

function formatPitShiftDetail(doc) {
  return {
    id: doc.id,
    label: doc.label || '',
    kind: doc.kind || '',
    competition: doc.competition || '',
    assignedUids: Array.isArray(doc.assignedUids) ? doc.assignedUids : [],
    assignedNames: Array.isArray(doc.assignedNames) ? doc.assignedNames : [],
    startMatch: typeof doc.startMatch === 'number' ? doc.startMatch : null,
    endMatch: typeof doc.endMatch === 'number' ? doc.endMatch : null,
    startsAt: doc.startsAt ?? null,
    endsAt: doc.endsAt ?? null,
    notes: doc.notes ?? null,
    importedFrom: doc.importedFrom ?? null,
    updatedAt: doc.updatedAt,
  };
}

module.exports = {
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
};
