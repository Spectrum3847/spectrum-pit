# Spectrum Pit MCP server

Read-only [Model Context Protocol](https://modelcontextprotocol.io) server over
this app's Firestore pit data, so an AI agent can answer questions about
tools, packing progress, loans, map pins, and the pit schedule without a human
retyping them into a chat window.

## Scope

This is a deliberately narrow cut:

- `inventoryItems`, `packingRecords`, `borrowRecords`, `mapLocations`, and
  `pitShifts` -- the five feature collections documented in
  `docs/database-plan.md`.
- Read-only. No tool here writes anything. Creating or editing any record
  still goes through the app, which enforces `firestore.rules`' shape checks
  and monotonic-`updatedAt` rule.

Deliberately left out:

- **`mapDiagrams` and `containerPhotos`.** These hold R2 object keys pointing
  at image bytes, not useful text records; an agent cannot render a diagram
  or a drawer photo from a key.
- **`userProfiles`, `bugReports`, `telemetry`, and `appConfig`.** Not pit
  feature data; none of them help an agent answer a pit-logistics question.
- **Write tools.** A write tool would need to reimplement the same field and
  monotonicity checks `firestore.rules` already enforces for the app, and a
  read-only server is far easier to reason about and to grant credentials to.

## Auth

A Firestore service-account credential via the `FIREBASE_SERVICE_ACCOUNT`
environment variable: the Admin SDK JSON key for `spectrumpit`, either raw or
base64-encoded (the repo's `GOOGLE_SERVICES_JSON` convention). Get one from
the Firebase console (`spectrumpit` > Project settings > Service accounts >
Generate new private key). Never commit the key; keep it out of shared
locations. The repo's `.gitignore` already excludes `serviceAccount*.json`.

**This is a broad, project-wide Admin SDK credential, not one scoped to just
these five collections** -- Firestore does not offer collection-level IAM. It
bypasses `firestore.rules` entirely, the same way any Admin SDK credential
does. Two things keep that acceptable for what this server does:

- Every read-only rule in `firestore.rules` already lets any signed-in team
  member read these collections in full, so this credential is not exposing
  anything a signed-in member could not already read -- it just skips the
  sign-in step for a tool that only reads.
- This server has no write path at all, so the credential's ability to write
  is never exercised here regardless of what it is capable of.

Treat the key file the same as any other Firestore admin credential, and run
this server locally on your own machine, not as a shared or hosted process.
If a hosted, team-wide version of this server is ever built, it needs its own
auth in front of it.

## Run it

```bash
cd mcp
pnpm install
FIREBASE_SERVICE_ACCOUNT="$(cat /path/to/service-account.json)" pnpm start
```

The server speaks MCP over stdio. To wire it into an MCP client (for example
Claude Desktop's `claude_desktop_config.json`, or any other client that
launches a stdio MCP server):

```json
{
  "mcpServers": {
    "spectrumpit": {
      "command": "node",
      "args": ["/absolute/path/to/spectrum-pit/mcp/index.js"],
      "env": {
        "FIREBASE_SERVICE_ACCOUNT": "<service account JSON, one line>"
      }
    }
  }
}
```

## Tools

| Tool | Purpose |
|---|---|
| `list_inventory_items` | List tools and where they live, filterable by `status`. |
| `get_inventory_item` | Full record for one item by id, including lab/pit locations and map reference. |
| `list_packing_records` | List packing pipeline records, filterable by `packingStatus`. Summaries only (whether a photo exists, not its object key). |
| `get_packing_record` | Full record for one packing record by id, including the photo object key. |
| `list_borrow_records` | List tool loans, filterable by `returned`. A record with `returned=false` and an `estimatedReturn` in the past is overdue. |
| `get_borrow_record` | Full record for one loan by id, including contact and check-in timestamps. |
| `list_map_locations` | List diagram pins, filterable by `mapType`. |
| `get_map_location` | Full pin by id, with normalized x/y coordinates. |
| `list_pit_shifts` | List schedule shifts, filterable by `competition`. Summaries only (assignee count, truncated notes). |
| `get_pit_shift` | Full shift by id, with assignees, match/wall-clock range, notes, and import origin. |
| `summarize_pit_shifts` | Per-competition shift counts with last-updated times. |

All list tools default to 25 results and cap at 100. Filtering and sorting
happen in JS after a single, unindexed Firestore `.where()` (or none), so
this server never needs a Firestore composite index.

## Tests

```bash
cd mcp
pnpm install
pnpm test
```

Tests cover the pure logic in `lib/` (filtering, sorting, limit clamping,
credential parsing, output shaping) against plain JS objects -- no Firestore
connection required.
