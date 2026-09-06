import test from 'node:test';
import assert from 'node:assert/strict';

import worker, { decodeUnverifiedUid, hasMemberRole, resolveMember } from '../src/index.mjs';

const ENV_BASE = { FIREBASE_PROJECT: 'spectrumpit', ALLOWED_ORIGINS: 'https://spectrumpit.web.app' };

function tokenFor(payload) {
  const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
  return `header.${body}.signature`;
}

function profile(roles) {
  return { fields: { roles: { arrayValue: { values: roles.map((r) => ({ stringValue: r })) } } } };
}

function fakeFirestore(expectedToken, roles, { status = 200 } = {}) {
  const calls = [];
  const impl = async (url, init) => {
    calls.push(url);
    const ok = status === 200 && init.headers.Authorization === `Bearer ${expectedToken}`;
    return {
      ok,
      status: ok ? 200 : 401,
      json: async () => profile(roles),
    };
  };
  impl.calls = calls;
  return impl;
}

function fakeBucket() {
  const objects = new Map();
  return {
    objects,
    async put(key, body, opts) {
      objects.set(key, { body, size: body.byteLength, httpMetadata: opts?.httpMetadata });
    },
    async get(key) {
      const found = objects.get(key);
      return found ? { ...found, body: found.body } : null;
    },
    async delete(key) {
      objects.delete(key);
    },
  };
}

function request(method, path, { token, type, body, origin } = {}) {
  const headers = {};
  if (token) headers.Authorization = `Bearer ${token}`;
  if (type) headers['Content-Type'] = type;
  if (origin) headers.Origin = origin;
  return new Request(`https://photos.example${path}`, { method, headers, body });
}

test('decodeUnverifiedUid pulls sub out of a base64url payload', () => {
  assert.equal(decodeUnverifiedUid(tokenFor({ sub: 'abc123' })), 'abc123');
});

test('decodeUnverifiedUid rejects a sub that could escape the profile path', () => {

  assert.equal(decodeUnverifiedUid(tokenFor({ sub: '../../appConfig/notifications' })), null);
  assert.equal(decodeUnverifiedUid(tokenFor({ sub: 'has/slash' })), null);
});

test('decodeUnverifiedUid rejects garbage and missing claims', () => {
  assert.equal(decodeUnverifiedUid('not-a-jwt'), null);
  assert.equal(decodeUnverifiedUid(tokenFor({})), null);
  assert.equal(decodeUnverifiedUid(tokenFor({ sub: 42 })), null);
});

test('hasMemberRole accepts each granted role and refuses viewer', () => {
  for (const role of ['pit', 'admin', 'developer']) {
    assert.equal(hasMemberRole(profile([role])), true, role);
  }
  assert.equal(hasMemberRole(profile(['viewer'])), false);
  assert.equal(hasMemberRole(profile([])), false);
  assert.equal(hasMemberRole({}), false);
});

test('hasMemberRole falls back to the legacy singular role string', () => {
  const legacyProfile = (role) => ({ fields: { role: { stringValue: role } } });
  for (const role of ['pit', 'admin', 'developer']) {
    assert.equal(hasMemberRole(legacyProfile(role)), true, role);
  }
  assert.equal(hasMemberRole(legacyProfile('viewer')), false);

  assert.equal(
    hasMemberRole({
      fields: {
        roles: { arrayValue: { values: [{ stringValue: 'viewer' }] } },
        role: { stringValue: 'admin' },
      },
    }),
    true,
  );
});

test('resolveMember passes the caller token straight to Firestore', async () => {
  const token = tokenFor({ sub: 'uid1' });
  const fetchImpl = fakeFirestore(token, ['admin']);
  assert.equal(await resolveMember(request('GET', '/photos', { token }), ENV_BASE, fetchImpl), 'uid1');
  assert.match(fetchImpl.calls[0], /projects\/spectrumpit\/databases\/\(default\)\/documents\/userProfiles\/uid1$/);
});

test('resolveMember refuses a token Firestore rejects', async () => {
  const token = tokenFor({ sub: 'uid1' });
  const fetchImpl = fakeFirestore(token, ['admin'], { status: 401 });
  assert.equal(await resolveMember(request('GET', '/photos', { token }), ENV_BASE, fetchImpl), null);
});

test('resolveMember refuses a viewer holding a perfectly valid token', async () => {
  const token = tokenFor({ sub: 'uid1' });
  assert.equal(
    await resolveMember(request('GET', '/photos', { token }), ENV_BASE, fakeFirestore(token, ['viewer'])),
    null,
  );
});

test('resolveMember refuses a missing or malformed header', async () => {
  const never = async () => assert.fail('should not have reached Firestore');
  assert.equal(await resolveMember(request('GET', '/photos'), ENV_BASE, never), null);
  const raw = new Request('https://photos.example/photos', { headers: { Authorization: 'abc' } });
  assert.equal(await resolveMember(raw, ENV_BASE, never), null);
});

async function withFirestore(token, roles, body) {
  const original = globalThis.fetch;
  globalThis.fetch = fakeFirestore(token, roles);
  try {
    return await body();
  } finally {
    globalThis.fetch = original;
  }
}

test('upload stores the image and returns a key the download route accepts', async () => {
  const token = tokenFor({ sub: 'uid1' });
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['pit'], async () => {
    const res = await worker.fetch(
      request('POST', '/photos', { token, type: 'image/jpeg', body: new Uint8Array([1, 2, 3]) }),
      env,
    );
    assert.equal(res.status, 201);
    const { key } = await res.json();
    assert.match(key, /\.jpg$/);
    assert.equal(env.PHOTOS.objects.get(key).httpMetadata.contentType, 'image/jpeg');

    const got = await worker.fetch(request('GET', `/photos/${key}`, { token }), env);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get('Content-Type'), 'image/jpeg');
    assert.equal(got.headers.get('Cache-Control'), 'private, max-age=86400');
  });
});

test('upload refuses a non-image content type', async () => {
  const token = tokenFor({ sub: 'uid1' });
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['pit'], async () => {
    const res = await worker.fetch(
      request('POST', '/photos', { token, type: 'text/html', body: '<script>' }),
      env,
    );
    assert.equal(res.status, 415);
    assert.equal(env.PHOTOS.objects.size, 0);
  });
});

test('upload refuses a body over the cap even when Content-Length lies', async () => {
  const token = tokenFor({ sub: 'uid1' });
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['pit'], async () => {
    const res = await worker.fetch(
      request('POST', '/photos', {
        token,
        type: 'image/png',
        body: new Uint8Array(2 * 1024 * 1024 + 1),
      }),
      env,
    );
    assert.equal(res.status, 413);
    assert.equal(env.PHOTOS.objects.size, 0);
  });
});

test('upload refuses an empty body', async () => {
  const token = tokenFor({ sub: 'uid1' });
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  await withFirestore(token, ['pit'], async () => {
    const res = await worker.fetch(
      request('POST', '/photos', { token, type: 'image/jpeg', body: new Uint8Array(0) }),
      env,
    );
    assert.equal(res.status, 400);
  });
});

test('every route refuses a viewer', async () => {
  const token = tokenFor({ sub: 'uid1' });
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  env.PHOTOS.objects.set('11111111-2222-3333-4444-555555555555.jpg', {
    body: new Uint8Array([1]),
    size: 1,
  });
  await withFirestore(token, ['viewer'], async () => {
    for (const req of [
      request('POST', '/photos', { token, type: 'image/jpeg', body: new Uint8Array([1]) }),
      request('GET', '/photos/11111111-2222-3333-4444-555555555555.jpg', { token }),
      request('DELETE', '/photos/11111111-2222-3333-4444-555555555555.jpg', { token }),
    ]) {
      assert.equal((await worker.fetch(req, env)).status, 403);
    }
    assert.equal(env.PHOTOS.objects.size, 1, 'viewer must not have deleted anything');
  });
});

test('a key the Worker did not mint is refused before touching the bucket', async () => {
  const token = tokenFor({ sub: 'uid1' });
  const bucket = fakeBucket();
  bucket.get = async () => assert.fail('should not have read the bucket');
  await withFirestore(token, ['admin'], async () => {
    for (const key of ['../appConfig', 'secret.txt', 'not-a-uuid.jpg']) {
      const res = await worker.fetch(request('GET', `/photos/${key}`, { token }), {
        ...ENV_BASE,
        PHOTOS: bucket,
      });
      assert.equal(res.status, 404, key);
    }
  });
});

test('download 404s for a well-formed key that is not there', async () => {
  const token = tokenFor({ sub: 'uid1' });
  await withFirestore(token, ['admin'], async () => {
    const res = await worker.fetch(
      request('GET', '/photos/11111111-2222-3333-4444-555555555555.jpg', { token }),
      { ...ENV_BASE, PHOTOS: fakeBucket() },
    );
    assert.equal(res.status, 404);
  });
});

test('delete removes the object', async () => {
  const token = tokenFor({ sub: 'uid1' });
  const key = '11111111-2222-3333-4444-555555555555.jpg';
  const env = { ...ENV_BASE, PHOTOS: fakeBucket() };
  env.PHOTOS.objects.set(key, { body: new Uint8Array([1]), size: 1 });
  await withFirestore(token, ['admin'], async () => {
    const res = await worker.fetch(request('DELETE', `/photos/${key}`, { token }), env);
    assert.equal(res.status, 204);
    assert.equal(env.PHOTOS.objects.size, 0);
  });
});

test('paths outside /photos are refused without a Firestore call', async () => {
  const never = async () => assert.fail('should not have reached Firestore');
  const original = globalThis.fetch;
  globalThis.fetch = never;
  try {
    const res = await worker.fetch(request('GET', '/'), { ...ENV_BASE, PHOTOS: fakeBucket() });
    assert.equal(res.status, 404);
  } finally {
    globalThis.fetch = original;
  }
});

test('CORS is echoed only for an allowed origin', async () => {
  const allowed = await worker.fetch(
    request('OPTIONS', '/photos', { origin: 'https://spectrumpit.web.app' }),
    ENV_BASE,
  );
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get('Access-Control-Allow-Origin'), 'https://spectrumpit.web.app');

  const denied = await worker.fetch(request('OPTIONS', '/photos', { origin: 'https://evil.example' }), ENV_BASE);
  assert.equal(denied.headers.get('Access-Control-Allow-Origin'), null);
});

test('CORS is echoed for the fixed preview site, and not for a channel host', async () => {

  const env = {
    ...ENV_BASE,
    ALLOWED_ORIGINS: `${ENV_BASE.ALLOWED_ORIGINS},https://spectrumpit-preview.web.app`,
  };
  const res = await worker.fetch(
    request('OPTIONS', '/photos', { origin: 'https://spectrumpit-preview.web.app' }),
    env,
  );
  assert.equal(res.status, 204);
  assert.equal(
    res.headers.get('Access-Control-Allow-Origin'),
    'https://spectrumpit-preview.web.app',
  );
  assert.equal(res.headers.get('Vary'), 'Origin');

  const channel = await worker.fetch(
    request('OPTIONS', '/photos', {
      origin: 'https://spectrumpit--pr-251-250-mxk6i7sz.web.app',
    }),
    env,
  );
  assert.equal(channel.headers.get('Access-Control-Allow-Origin'), null);
});
