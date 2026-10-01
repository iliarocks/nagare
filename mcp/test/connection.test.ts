import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
import test, { type TestContext } from 'node:test';
import type { Env } from '../src/connection.js';
import type { CloudKitRecord } from '../src/cloudkit.js';

// Exercise the real Connection/CloudKit/Nagare path; only the Workers base class
// and durable storage are replaced in these Node tests.
registerHooks({ resolve(specifier, context, next) {
  return specifier === 'cloudflare:workers'
    ? { url: 'data:text/javascript,export class DurableObject { constructor(ctx, env) { this.ctx = ctx; this.env = env; } }', shortCircuit: true }
    : next(specifier, context);
} });
const { Connection } = await import('../src/connection.js');

const zoneID = { zoneName: 'com.apple.coredata.cloudkit.zone', ownerRecordName: 'owner-1' };
const env = { CLOUDKIT_CONTAINER: 'iCloud.test.nagare', CLOUDKIT_ENVIRONMENT: 'development', CLOUDKIT_API_TOKEN: 'private-api-token' } as Env;
const firstId = '00000000-0000-0000-0000-000000000001';
const secondId = '00000000-0000-0000-0000-000000000002';

function project(id = firstId, title = 'Project', order = 'i'): CloudKitRecord {
  return {
    recordName: `CD_Project_${id}`, recordType: 'CD_Project', recordChangeTag: 'v1',
    fields: { CD_id: { value: id }, CD_title: { value: title }, CD_order: { value: order } },
  };
}

function gate() {
  let open!: () => void;
  const promise = new Promise<void>(resolve => { open = resolve; });
  return { promise, open };
}

function setup() {
  const values = new Map<string, unknown>();
  const storage = {
    beforePut: undefined as undefined | ((value: unknown) => Promise<void>),
    async get(key: string) { return structuredClone(values.get(key)); },
    async put(key: string, value: unknown) {
      await storage.beforePut?.(value);
      values.set(key, structuredClone(value));
    },
  };
  const connection = new Connection({ storage } as unknown as DurableObjectState, env);
  const settings = () => values.get('connection') as { token: string; timeZone: string; zoneID: typeof zoneID } | undefined;
  return { connection, values, storage, settings };
}

function intercept(t: TestContext, handler: (url: URL, body?: Record<string, unknown>) => Response | Promise<Response>) {
  t.mock.method(globalThis, 'fetch', (input: unknown, init?: RequestInit) => handler(
    new URL(String(input)), init?.body ? JSON.parse(String(init.body)) : undefined,
  ));
}

function response(body: unknown, token: string) {
  return Response.json(body, { headers: { 'x-apple-cloudkit-web-auth-token': token } });
}

test('overlapping calls wait for the preceding operation and persisted token rotation', async t => {
  const { connection, storage, settings } = setup();
  const saving = gate();
  const allowSave = gate();
  const tokens: (string | null)[] = [];
  intercept(t, url => {
    tokens.push(url.searchParams.get('ckWebAuthToken'));
    if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, 'token-1');
    return response({ records: [project()] }, `token-${tokens.length}`);
  });
  await connection.configure('initial-token', 'America/Los_Angeles');
  storage.beforePut = async value => {
    if ((value as { token: string }).token === 'token-2') {
      saving.open();
      await allowSave.promise;
    }
  };
  const first = connection.run({ name: 'list_projects' });
  const second = connection.run({ name: 'list_projects' });
  await saving.promise;
  assert.deepEqual(tokens, ['initial-token', 'token-1']);
  assert.equal(settings()?.token, 'token-1');
  allowSave.open();
  assert.deepEqual((await Promise.all([first, second])).map(result => result.ok), [true, true]);
  assert.deepEqual(tokens, ['initial-token', 'token-1', 'token-2']);
  assert.equal(settings()?.token, 'token-3');
});

test('selects the Core Data zone and follows every indexed-query page', async t => {
  const { connection, values, settings } = setup();
  const markers: unknown[] = [];
  intercept(t, (url, body) => {
    if (url.pathname.endsWith('zones/list')) return response({ zones: [
      { zoneID: { zoneName: '_defaultZone' } }, { zoneID: { zoneName: 'unrelated' } }, { zoneID },
    ] }, 'signed-in');
    assert.deepEqual(body?.zoneID, zoneID);
    assert.deepEqual(body?.query, {
      recordType: 'CD_Project',
      filterBy: [{ fieldName: 'CD_entityName', comparator: 'EQUALS', fieldValue: { value: 'Project', type: 'STRING' } }],
    });
    markers.push(body?.continuationMarker);
    return body?.continuationMarker === undefined
      ? response({ records: [project(secondId, 'Second', 'z')], continuationMarker: 'next-page' }, 'page-1-token')
      : response({ records: [project(firstId, 'First', 'a')] }, 'page-2-token');
  });
  await connection.configure('initial', 'America/Los_Angeles');
  const result = await connection.run({ name: 'list_projects' });
  assert.ok(result.ok);
  assert.deepEqual((result.data as { title: string }[]).map(item => item.title), ['First', 'Second']);
  assert.deepEqual(markers, [undefined, 'next-page']);
  assert.deepEqual(settings(), { token: 'page-2-token', timeZone: 'America/Los_Angeles', zoneID });
  assert.deepEqual([...values.keys()], ['connection']);
});

test('different users keep separate credentials and results during concurrent requests', async t => {
  const alice = setup();
  const bob = setup();
  intercept(t, url => {
    const token = url.searchParams.get('ckWebAuthToken')!;
    const aliceRequest = token.startsWith('alice-');
    const user = aliceRequest ? 'alice' : 'bob';
    if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, `${user}-configured`);
    return response({ records: [project(aliceRequest ? firstId : secondId, `${user}'s project`)] }, `${user}-rotated`);
  });
  await Promise.all([
    alice.connection.configure('alice-initial', 'America/Los_Angeles'),
    bob.connection.configure('bob-initial', 'Europe/London'),
  ]);
  const [aliceResult, bobResult] = await Promise.all([
    alice.connection.run({ name: 'list_projects' }), bob.connection.run({ name: 'list_projects' }),
  ]);
  assert.ok(aliceResult.ok && bobResult.ok);
  assert.equal((aliceResult.data as { title: string }[])[0].title, "alice's project");
  assert.equal((bobResult.data as { title: string }[])[0].title, "bob's project");
  assert.equal(alice.settings()?.token, 'alice-rotated');
  assert.equal(bob.settings()?.token, 'bob-rotated');
  assert.equal(bob.settings()?.timeZone, 'Europe/London');
  assert.equal(JSON.stringify([...alice.values.values()]).includes('bob'), false);
});

test('missing Core Data data never creates a configured connection', async t => {
  const { connection, values } = setup();
  intercept(t, () => response({ zones: [{ zoneID: { zoneName: '_defaultZone' } }] }, 'rotated'));
  await assert.rejects(connection.configure('token', 'UTC'), /Open Nagare with iCloud sync enabled/);
  assert.equal(values.size, 0);
  assert.deepEqual(await connection.run({ name: 'list_projects' }), {
    ok: false, code: 'AUTHENTICATION_REQUIRED', message: 'Reconnect Nagare to your agent.',
  });
});

test('upstream failures expose no token or private reason and do not poison later calls', async t => {
  const { connection, settings } = setup();
  let fail = true;
  intercept(t, url => {
    if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, 'private-user-token');
    if (fail) {
      fail = false;
      return Response.json({ serverErrorCode: 'THROTTLED', reason: 'private contents and private-user-token', redirectURL: 'https://apple.example?token=private-api-token' }, {
        status: 429, headers: { 'x-apple-cloudkit-session': 'rotated-after-error' },
      });
    }
    assert.equal(url.searchParams.get('ckWebAuthToken'), 'rotated-after-error');
    return response({ records: [project()] }, 'recovered');
  });
  await connection.configure('initial', 'UTC');
  const failure = await connection.run({ name: 'list_projects' });
  assert.deepEqual(failure, { ok: false, code: 'THROTTLED', message: 'CloudKit could not complete the operation (THROTTLED).' });
  assert.ok(!JSON.stringify(failure).includes('private'));
  assert.equal((await connection.run({ name: 'list_projects' })).ok, true);
  assert.equal(settings()?.token, 'recovered');
});
