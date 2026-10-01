import assert from 'node:assert/strict';
import { test } from 'node:test';
import { CloudKitClient, CloudKitError, type CloudKitOptions, type CloudKitRecord } from '../src/cloudkit.js';

const zoneID = { zoneName: 'com.apple.coredata.cloudkit.zone' };
const record: CloudKitRecord = {
  recordName: 'task-record',
  recordType: 'CD_Todo',
  recordChangeTag: 'original',
  fields: { CD_title: { value: 'Test task' }, CD_scheduledDate: { value: 1_759_359_600_000, type: 'TIMESTAMP' } },
};
const base = { container: 'iCloud.test.nagare', environment: 'development' as const, apiToken: 'api+/=', webAuthToken: 'web+/=' };
const json = (value: unknown, init?: ResponseInit) => Response.json(value, init);

function mockClient(handler: (url: URL, init: RequestInit) => Response | Promise<Response>, extra: Partial<CloudKitOptions> = {}) {
  return new CloudKitClient({
    ...base,
    ...extra,
    fetch: (async (input, init) => handler(new URL(String(input)), init!)) as typeof fetch,
  });
}

test('uses the caller endpoint and encodes credentials without altering them', async () => {
  const client = mockClient((url, init) => {
    assert.equal(url.pathname, '/database/1/iCloud.test.nagare/development/public/users/caller');
    assert.equal(url.searchParams.get('ckAPIToken'), base.apiToken);
    assert.equal(url.searchParams.get('ckWebAuthToken'), base.webAuthToken);
    assert.equal(init.method, 'GET');
    assert.equal(init.redirect, 'manual');
    return json({ users: [{ userRecordName: 'user-1', nameComponents: { givenName: 'Private' } }] });
  });
  assert.deepEqual(await client.currentUser(), { userRecordName: 'user-1' });
});

test('rejects HTTP redirects without following them or accepting their tokens', async () => {
  let requests = 0;
  const saved: string[] = [];
  const client = mockClient((_url, init) => {
    requests++;
    assert.equal(init.redirect, 'manual');
    return new Response('Redirect body is not JSON', {
      status: 302,
      headers: { Location: 'https://unexpected.example/', 'x-apple-cloudkit-session': 'untrusted-token' },
    });
  }, { onWebAuthToken: token => { saved.push(token); } });
  await assert.rejects(client.currentUser(), { code: 'UNEXPECTED_REDIRECT', status: 302 });
  assert.equal(requests, 1);
  assert.deepEqual(saved, []);
});

test('returns the Apple authorization redirect without logging credentials in its error message', async () => {
  const redirectURL = 'https://idmsa.apple.com/signin?client=test';
  const client = mockClient(() => json({ serverErrorCode: 'AUTHENTICATION_REQUIRED', redirectURL }, { status: 421 }), { webAuthToken: undefined });
  await assert.rejects(client.currentUser(), error => {
    assert.ok(error instanceof CloudKitError);
    assert.equal(error.code, 'AUTHENTICATION_REQUIRED');
    assert.equal(error.status, 421);
    assert.equal(error.redirectURL, redirectURL);
    assert.ok(!error.message.includes(base.apiToken));
    return true;
  });
});

test('serializes requests and waits for rotated credentials to be persisted', async () => {
  let releasePersistence!: () => void;
  const persistence = new Promise<void>(resolve => { releasePersistence = resolve; });
  let observedPersistence!: () => void;
  const saving = new Promise<void>(resolve => { observedPersistence = resolve; });
  const seenTokens: (string | null)[] = [];
  const client = mockClient(url => {
    seenTokens.push(url.searchParams.get('ckWebAuthToken'));
    return json({ zones: [{ zoneID }] }, { headers: { 'x-apple-cloudkit-web-auth-token': 'rotated' } });
  }, {
    onWebAuthToken: async () => { observedPersistence(); await persistence; },
  });
  const first = client.listZones();
  const second = client.listZones();
  await saving;
  assert.deepEqual(seenTokens, [base.webAuthToken]);
  releasePersistence();
  await Promise.all([first, second]);
  assert.deepEqual(seenTokens, [base.webAuthToken, 'rotated']);
});

test('persists a session-header rotation even when a record operation fails', async () => {
  const saved: string[] = [];
  const client = mockClient(() => json({ serverErrorCode: 'CONFLICT' }, {
    status: 409, headers: { 'x-apple-cloudkit-session': 'new-session' },
  }), { onWebAuthToken: token => { saved.push(token); } });
  await assert.rejects(client.listZones(), { code: 'CONFLICT' });
  assert.deepEqual(saved, ['new-session']);
});

test('sends zone-scoped queries and preserves pagination and date values', async () => {
  const client = mockClient((url, init) => {
    assert.ok(url.pathname.endsWith('/private/records/query'));
    assert.deepEqual(JSON.parse(String(init.body)), {
      zoneID, continuationMarker: 'page-1', query: { recordType: 'CD_Todo' },
    });
    return json({ records: [record], continuationMarker: 'page-2' });
  });
  assert.deepEqual(await client.query({ recordType: 'CD_Todo', zoneID, continuationMarker: 'page-1' }), {
    records: [record], continuationMarker: 'page-2',
  });
});

test('looks up exact record names in the supplied zone', async () => {
  const client = mockClient((url, init) => {
    assert.ok(url.pathname.endsWith('/private/records/lookup'));
    assert.deepEqual(JSON.parse(String(init.body)), { zoneID, records: [{ recordName: 'task-record' }] });
    return json({ records: [record] });
  });
  assert.deepEqual(await client.lookup({ zoneID, recordNames: ['task-record'] }), [record]);
});

test('applies narrow patches atomically with optimistic concurrency', async () => {
  const patch: CloudKitRecord = { ...record, fields: { CD_title: { value: 'Renamed' } } };
  const client = mockClient((url, init) => {
    assert.ok(url.pathname.endsWith('/private/records/modify'));
    assert.deepEqual(JSON.parse(String(init.body)), {
      zoneID, atomic: true, operations: [{ operationType: 'update', record: patch }],
    });
    return json({ records: [{ ...record, recordChangeTag: 'next' }] });
  });
  assert.equal((await client.modify({ zoneID, operations: [{ operationType: 'update', record: patch }] }))[0].recordChangeTag, 'next');
});

test('rejects updates without a change tag before making any request', async () => {
  const client = mockClient(() => { throw new Error('Must not fetch'); });
  await assert.rejects(client.modify({ zoneID, operations: [{ operationType: 'update', record: { ...record, recordChangeTag: undefined } }] }), {
    code: 'MISSING_RECORD_CHANGE_TAG',
  });
});

test('surfaces record failures in a successful HTTP response without retrying a write', async () => {
  let count = 0;
  const client = mockClient(() => {
    count++;
    return json({ records: [{ recordName: record.recordName, serverErrorCode: 'CONFLICT', reason: 'private server detail' }] });
  });
  await assert.rejects(client.modify({ zoneID, operations: [{ operationType: 'update', record }] }), error => {
    assert.ok(error instanceof CloudKitError);
    assert.equal(error.code, 'CONFLICT');
    assert.deepEqual(error.failures, [{ recordName: record.recordName, serverErrorCode: 'CONFLICT' }]);
    return true;
  });
  assert.equal(count, 1);
});

test('network and invalid-body errors do not expose upstream bodies or URLs', async () => {
  const client = mockClient(url => { throw new Error(`Fetch failed at ${url}`); });
  await assert.rejects(client.listZones(), error => {
    assert.ok(error instanceof CloudKitError);
    assert.equal(error.code, 'NETWORK_ERROR');
    assert.ok(!String(error).includes(base.apiToken));
    return true;
  });
  const invalid = mockClient(() => new Response('Sensitive upstream proxy error', { status: 502 }));
  await assert.rejects(invalid.listZones(), { code: 'UNEXPECTED_SERVER_RESPONSE', status: 502 });
});

test('refuses malformed collections and stops when token persistence fails', async () => {
  const malformed = mockClient(() => json({ zones: null }));
  await assert.rejects(malformed.listZones(), { code: 'UNEXPECTED_SERVER_RESPONSE' });
  const client = mockClient(() => json({ zones: [] }, { headers: { 'x-apple-cloudkit-session': 'new' } }), {
    onWebAuthToken: () => { throw new Error('Database unavailable'); },
  });
  await assert.rejects(client.listZones(), { code: 'AUTH_PERSIST_ERROR' });
});
