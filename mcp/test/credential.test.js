'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { parseServiceAccount } = require('../lib/credential');

const SAMPLE = { project_id: 'spectrumpit', client_email: 'x@y.iam.gserviceaccount.com' };

test('parseServiceAccount reads raw JSON', () => {
  assert.deepEqual(parseServiceAccount(JSON.stringify(SAMPLE)), SAMPLE);
});

test('parseServiceAccount reads base64-encoded JSON', () => {
  const encoded = Buffer.from(JSON.stringify(SAMPLE), 'utf8').toString('base64');
  assert.deepEqual(parseServiceAccount(encoded), SAMPLE);
});

test('parseServiceAccount trims surrounding whitespace before detecting the format', () => {
  assert.deepEqual(parseServiceAccount(`  ${JSON.stringify(SAMPLE)}  \n`), SAMPLE);
});
