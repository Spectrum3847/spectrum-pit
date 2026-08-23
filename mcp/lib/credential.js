// Service-account credential parsing. FIREBASE_SERVICE_ACCOUNT holds either
// raw JSON or the repo's base64-encoded JSON convention (GOOGLE_SERVICES_JSON).

'use strict';

function parseServiceAccount(raw) {
  const trimmed = raw.trim();
  if (trimmed.startsWith('{')) {
    return JSON.parse(trimmed);
  }
  return JSON.parse(Buffer.from(trimmed, 'base64').toString('utf8'));
}

module.exports = { parseServiceAccount };
