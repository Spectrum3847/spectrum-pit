// Read-only MCP server over Spectrum Pit's Firestore pit data. Exposes
// inventoryItems, packingRecords, borrowRecords, mapLocations, and
// pitShifts -- the five feature collections documented in
// docs/database-plan.md -- as MCP tools over stdio, so a local AI agent can
// answer questions about tools, packing progress, loans, maps, and the pit
// schedule without a human retyping them into a chat window.
//
// Deliberately narrow:
// - Read-only. No tool here writes anything; records can only be created or
//   edited through the app itself, which applies firestore.rules' shape and
//   monotonic-updatedAt checks.
// - Only the five feature collections. mapDiagrams/containerPhotos (R2 key
//   pointers), userProfiles, telemetry, bugReports, and appConfig are out of
//   scope for this server.
//
// Auth: a Firestore service-account credential via FIREBASE_SERVICE_ACCOUNT
// (raw or base64 JSON, see lib/credential.js). This is a project-wide Admin
// SDK credential, not a scoped one -- Firestore offers no collection-level
// IAM. See README.md's security note for why that is acceptable here: every
// read-only rule in firestore.rules already lets any signed-in member read
// these collections in full, and this server has no write path at all.
// Run this locally, on your own machine -- it is not a hosted service.

'use strict';

const { initializeApp, cert } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { McpServer } = require('@modelcontextprotocol/sdk/server/mcp.js');
const {
  StdioServerTransport,
} = require('@modelcontextprotocol/sdk/server/stdio.js');
const { z } = require('zod');

const { parseServiceAccount } = require('./lib/credential');
const { clampLimit } = require('./lib/params');
const {
  selectInventoryItems,
  selectPackingRecords,
  selectBorrowRecords,
  selectMapLocations,
  selectPitShifts,
  summarizePitShifts,
} = require('./lib/query');
const {
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
} = require('./lib/format');

// Every list tool pulls at most this many raw documents from Firestore
// before filtering/sorting/limiting in JS. Bounds the read even when a
// caller asks for a broad, unfiltered query. See lib/query.js for why
// filtering happens here instead of via a second `.where()` clause.
const RAW_FETCH_CAP = 500;

const packageJson = require('./package.json');

const INVENTORY_STATUS_SCHEMA = z
  .enum(['inLab', 'inPit', 'borrowed'])
  .optional()
  .describe('Item status filter.');

const PACKING_STATUS_SCHEMA = z
  .enum(['notStarted', 'packing', 'staging', 'loading', 'ready'])
  .optional()
  .describe('Packing pipeline stage filter.');

const MAP_TYPE_SCHEMA = z
  .enum(['lab', 'pit', 'vehicle'])
  .optional()
  .describe('Which diagram the location sits on.');

const LIMIT_SCHEMA = z.number().int().optional().describe('Max results (default 25, max 100).');

function jsonResult(value) {
  return { content: [{ type: 'text', text: JSON.stringify(value, null, 2) }] };
}

function initFirestore() {
  const rawCredential = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!rawCredential) {
    throw new Error(
      'FIREBASE_SERVICE_ACCOUNT is not set. See mcp/README.md for setup.',
    );
  }
  initializeApp({ credential: cert(parseServiceAccount(rawCredential)) });
  return getFirestore();
}

/**
 * Fetches up to `cap` documents from a collection, optionally pushing a
 * single equality filter down to Firestore. `.where()` is never combined
 * with `.orderBy()`, so no collection here needs a composite index;
 * sorting happens in JS afterwards.
 */
async function fetchDocs(db, collectionName, filter, cap) {
  let query = db.collection(collectionName);
  if (filter) {
    query = query.where(filter.field, filter.op, filter.value);
  }
  const snapshot = await query.limit(cap).get();
  return snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
}

function getDocOrError(db, collectionName, label, id) {
  return db.collection(collectionName).doc(id).get().then((doc) => {
    if (!doc.exists) {
      return { error: `No ${label} with id "${id}".` };
    }
    return { id: doc.id, ...doc.data() };
  });
}

function registerTools(server, db) {
  server.registerTool(
    'list_inventory_items',
    {
      title: 'List inventory items',
      description:
        'Lists inventory items (tools and where they live), optionally ' +
        'filtered by status. Returns summaries -- use get_inventory_item ' +
        'for the full record including any map reference.',
      inputSchema: {
        status: INVENTORY_STATUS_SCHEMA,
        limit: LIMIT_SCHEMA,
      },
    },
    async ({ status, limit }) => {
      const normalizedLimit = clampLimit(limit);
      let filter = null;
      if (status) filter = { field: 'status', op: '==', value: status };
      const docs = await fetchDocs(db, 'inventoryItems', filter, RAW_FETCH_CAP);
      const selected = selectInventoryItems(docs, {
        status,
        limit: normalizedLimit,
      });
      return jsonResult({
        count: selected.length,
        items: selected.map(formatInventoryItemSummary),
      });
    },
  );

  server.registerTool(
    'get_inventory_item',
    {
      title: 'Get inventory item',
      description: 'Fetches one inventory item by id, with its lab and pit locations and map reference.',
      inputSchema: {
        id: z.string().describe('The inventoryItems document id.'),
      },
    },
    async ({ id }) => {
      const doc = await getDocOrError(db, 'inventoryItems', 'inventory item', id);
      if (doc.error) return jsonResult(doc);
      return jsonResult(formatInventoryItemDetail(doc));
    },
  );

  server.registerTool(
    'list_packing_records',
    {
      title: 'List packing records',
      description:
        'Lists event packing pipeline records, optionally filtered by ' +
        'packingStatus. Returns summaries -- use get_packing_record for ' +
        'the photo object key.',
      inputSchema: {
        packingStatus: PACKING_STATUS_SCHEMA,
        limit: LIMIT_SCHEMA,
      },
    },
    async ({ packingStatus, limit }) => {
      const normalizedLimit = clampLimit(limit);
      let filter = null;
      if (packingStatus) {
        filter = { field: 'packingStatus', op: '==', value: packingStatus };
      }
      const docs = await fetchDocs(db, 'packingRecords', filter, RAW_FETCH_CAP);
      const selected = selectPackingRecords(docs, {
        packingStatus,
        limit: normalizedLimit,
      });
      return jsonResult({
        count: selected.length,
        records: selected.map(formatPackingRecordSummary),
      });
    },
  );

  server.registerTool(
    'get_packing_record',
    {
      title: 'Get packing record',
      description: 'Fetches one packing record by id, with its pipeline stage and photo object key.',
      inputSchema: {
        id: z.string().describe('The packingRecords document id.'),
      },
    },
    async ({ id }) => {
      const doc = await getDocOrError(db, 'packingRecords', 'packing record', id);
      if (doc.error) return jsonResult(doc);
      return jsonResult(formatPackingRecordDetail(doc));
    },
  );

  server.registerTool(
    'list_borrow_records',
    {
      title: 'List borrow records',
      description:
        'Lists tool loan records, optionally filtered by returned status. ' +
        'Returns summaries -- use get_borrow_record for contact details ' +
        'and check-in timestamps. A record with returned=false and an ' +
        'estimatedReturn in the past is overdue.',
      inputSchema: {
        returned: z.boolean().optional().describe('Filter by whether the tool has been returned.'),
        limit: LIMIT_SCHEMA,
      },
    },
    async ({ returned, limit }) => {
      const normalizedLimit = clampLimit(limit);
      let filter = null;
      if (returned !== undefined) {
        filter = { field: 'returned', op: '==', value: returned };
      }
      const docs = await fetchDocs(db, 'borrowRecords', filter, RAW_FETCH_CAP);
      const selected = selectBorrowRecords(docs, {
        returned,
        limit: normalizedLimit,
      });
      return jsonResult({
        count: selected.length,
        records: selected.map(formatBorrowRecordSummary),
      });
    },
  );

  server.registerTool(
    'get_borrow_record',
    {
      title: 'Get borrow record',
      description: 'Fetches one borrow record by id, with contact info and checkout/check-in timestamps.',
      inputSchema: {
        id: z.string().describe('The borrowRecords document id.'),
      },
    },
    async ({ id }) => {
      const doc = await getDocOrError(db, 'borrowRecords', 'borrow record', id);
      if (doc.error) return jsonResult(doc);
      return jsonResult(formatBorrowRecordDetail(doc));
    },
  );

  server.registerTool(
    'list_map_locations',
    {
      title: 'List map locations',
      description:
        'Lists named pins on the lab, pit, or vehicle diagrams, optionally ' +
        'filtered by mapType. Returns summaries -- use get_map_location ' + 'for pin coordinates.',
      inputSchema: {
        mapType: MAP_TYPE_SCHEMA,
        limit: LIMIT_SCHEMA,
      },
    },
    async ({ mapType, limit }) => {
      const normalizedLimit = clampLimit(limit);
      let filter = null;
      if (mapType) filter = { field: 'mapType', op: '==', value: mapType };
      const docs = await fetchDocs(db, 'mapLocations', filter, RAW_FETCH_CAP);
      const selected = selectMapLocations(docs, {
        mapType,
        limit: normalizedLimit,
      });
      return jsonResult({
        count: selected.length,
        locations: selected.map(formatMapLocationSummary),
      });
    },
  );

  server.registerTool(
    'get_map_location',
    {
      title: 'Get map location',
      description: 'Fetches one map location by id, with its normalized x/y coordinates on the diagram.',
      inputSchema: {
        id: z.string().describe('The mapLocations document id.'),
      },
    },
    async ({ id }) => {
      const doc = await getDocOrError(db, 'mapLocations', 'map location', id);
      if (doc.error) return jsonResult(doc);
      return jsonResult(formatMapLocationDetail(doc));
    },
  );

  server.registerTool(
    'list_pit_shifts',
    {
      title: 'List pit shifts',
      description:
        'Lists pit team schedule shifts, optionally filtered by ' +
        'competition. Returns summaries -- use get_pit_shift for the full ' +
        'assignee lists and notes.',
      inputSchema: {
        competition: z.string().optional().describe('Exact competition name, e.g. "Week 0".'),
        limit: LIMIT_SCHEMA,
      },
    },
    async ({ competition, limit }) => {
      const normalizedLimit = clampLimit(limit);
      let filter = null;
      if (competition) {
        filter = { field: 'competition', op: '==', value: competition };
      }
      const docs = await fetchDocs(db, 'pitShifts', filter, RAW_FETCH_CAP);
      const selected = selectPitShifts(docs, {
        competition,
        limit: normalizedLimit,
      });
      return jsonResult({
        count: selected.length,
        shifts: selected.map(formatPitShiftSummary),
      });
    },
  );

  server.registerTool(
    'get_pit_shift',
    {
      title: 'Get pit shift',
      description: 'Fetches one pit shift by id, with assigned people, match or wall-clock range, and notes.',
      inputSchema: {
        id: z.string().describe('The pitShifts document id.'),
      },
    },
    async ({ id }) => {
      const doc = await getDocOrError(db, 'pitShifts', 'pit shift', id);
      if (doc.error) return jsonResult(doc);
      return jsonResult(formatPitShiftDetail(doc));
    },
  );

  server.registerTool(
    'summarize_pit_shifts',
    {
      title: 'Summarize pit shifts per competition',
      description:
        'Counts pit schedule shifts per competition, so an agent can see ' +
        'which competitions have schedule data without reading every shift.',
      inputSchema: {},
    },
    async () => {
      const docs = await fetchDocs(db, 'pitShifts', null, RAW_FETCH_CAP);
      return jsonResult(summarizePitShifts(docs));
    },
  );
}

async function main() {
  const db = initFirestore();
  const server = new McpServer({
    name: 'spectrumpit',
    version: packageJson.version || '0.0.0',
  });
  registerTools(server, db);

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = { registerTools, fetchDocs, initFirestore };
