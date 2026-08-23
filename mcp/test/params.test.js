'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { clampLimit, DEFAULT_LIMIT, MAX_LIMIT } = require('../lib/params');

test('clampLimit defaults when omitted', () => {
  assert.equal(clampLimit(undefined), DEFAULT_LIMIT);
  assert.equal(clampLimit(null), DEFAULT_LIMIT);
});

test('clampLimit defaults on a non-numeric or non-positive value', () => {
  assert.equal(clampLimit('not a number'), DEFAULT_LIMIT);
  assert.equal(clampLimit(0), DEFAULT_LIMIT);
  assert.equal(clampLimit(-5), DEFAULT_LIMIT);
});

test('clampLimit passes through an in-range value', () => {
  assert.equal(clampLimit(10), 10);
});

test('clampLimit truncates a fractional value', () => {
  assert.equal(clampLimit(10.9), 10);
});

test('clampLimit caps above the maximum', () => {
  assert.equal(clampLimit(9999), MAX_LIMIT);
});
