const MEMBER_ROLES = ['pit', 'admin', 'developer'];

const EXTENSION_BY_TYPE = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/heic': 'heic',
};

const MAX_BYTES = 2 * 1024 * 1024;

const KEY_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.[a-z]{3,4}$/;

export function decodeUnverifiedUid(token) {
  const payload = token.split('.')[1];
  if (!payload) return null;
  const base64 = payload.replaceAll('-', '+').replaceAll('_', '/');
  const padded = base64.padEnd(base64.length + ((4 - (base64.length % 4)) % 4), '=');
  let sub;
  try {
    sub = JSON.parse(atob(padded)).sub;
  } catch {
    return null;
  }

  return typeof sub === 'string' && /^[A-Za-z0-9]{1,128}$/.test(sub) ? sub : null;
}

export function hasMemberRole(profile) {
  const fields = profile?.fields ?? {};
  const values = fields.roles?.arrayValue?.values ?? [];
  if (values.some((v) => MEMBER_ROLES.includes(v?.stringValue))) return true;

  const legacyRole = fields.role?.stringValue;
  return typeof legacyRole === 'string' && MEMBER_ROLES.includes(legacyRole);
}

export async function resolveMember(request, env, fetchImpl = fetch) {
  const header = request.headers.get('Authorization') ?? '';
  if (!header.startsWith('Bearer ')) return null;
  const token = header.slice('Bearer '.length).trim();
  if (!token) return null;

  const uid = decodeUnverifiedUid(token);
  if (!uid) return null;

  const url =
    `https://firestore.googleapis.com/v1/projects/${env.FIREBASE_PROJECT}` +
    `/databases/(default)/documents/userProfiles/${encodeURIComponent(uid)}`;
  const res = await fetchImpl(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!res.ok) return null;

  return hasMemberRole(await res.json()) ? uid : null;
}

function corsHeaders(request, env) {
  const origin = request.headers.get('Origin');
  const allowed = (env.ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  if (!origin) return {};
  if (!allowed.includes(origin)) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function problem(status, message, cors) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { 'Content-Type': 'application/json', ...cors },
  });
}

async function upload(request, env, cors) {
  const type = (request.headers.get('Content-Type') ?? '').split(';')[0].trim();
  const extension = EXTENSION_BY_TYPE[type];
  if (!extension) return problem(415, 'Unsupported image type', cors);

  const declared = Number(request.headers.get('Content-Length'));
  if (Number.isFinite(declared) && declared > MAX_BYTES) {
    return problem(413, 'Image too large', cors);
  }

  const body = await request.arrayBuffer();
  if (body.byteLength === 0) return problem(400, 'Empty body', cors);
  if (body.byteLength > MAX_BYTES) return problem(413, 'Image too large', cors);

  const key = `${crypto.randomUUID()}.${extension}`;
  await env.PHOTOS.put(key, body, { httpMetadata: { contentType: type } });
  return new Response(JSON.stringify({ key }), {
    status: 201,
    headers: { 'Content-Type': 'application/json', ...cors },
  });
}

async function download(env, key, cors) {
  const object = await env.PHOTOS.get(key);
  if (!object) return problem(404, 'Not found', cors);
  return new Response(object.body, {
    headers: {
      'Content-Type': object.httpMetadata?.contentType ?? 'application/octet-stream',
      'Content-Length': String(object.size),

      'Cache-Control': 'private, max-age=86400',
      ...cors,
    },
  });
}

export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }

    const { pathname } = new URL(request.url);
    if (pathname !== '/photos' && !pathname.startsWith('/photos/')) {
      return problem(404, 'Not found', cors);
    }

    const uid = await resolveMember(request, env);
    if (!uid) return problem(403, 'Not a member', cors);

    const key = pathname === '/photos' ? '' : pathname.slice('/photos/'.length);

    if (request.method === 'POST' && !key) return upload(request, env, cors);
    if (!key || !KEY_PATTERN.test(key)) return problem(404, 'Not found', cors);
    if (request.method === 'GET') return download(env, key, cors);
    if (request.method === 'DELETE') {

      await env.PHOTOS.delete(key);
      return new Response(null, { status: 204, headers: cors });
    }
    return problem(405, 'Method not allowed', cors);
  },
};
