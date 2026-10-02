import assert from 'node:assert/strict';
import { registerHooks } from 'node:module';
import test, { type TestContext } from 'node:test';
import type { Env, Operation } from '../src/connection.js';
import type { CloudKitRecord } from '../src/cloudkit.js';
import type { TaskInfo } from '../src/nagare.js';

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
    fields: { CD_entityName: { value: 'Project' }, CD_id: { value: id }, CD_title: { value: title }, CD_order: { value: order } },
  };
}

function gate() {
  let open!: () => void;
  const promise = new Promise<void>(resolve => { open = resolve; });
  return { promise, open };
}

function setup(environment: Env['CLOUDKIT_ENVIRONMENT'] = 'development') {
  const values = new Map<string, unknown>();
  const storage = {
    alarmAt: null as number | null,
    beforePut: undefined as undefined | ((value: unknown) => Promise<void>),
    async get(key: string) { return structuredClone(values.get(key)); },
    async put(key: string, value: unknown) {
      await storage.beforePut?.(value);
      values.set(key, structuredClone(value));
    },
    async setAlarm(timestamp: number) { storage.alarmAt = timestamp; },
    async deleteAll() { values.clear(); storage.alarmAt = null; },
    async transaction<T>(action: (transaction: Pick<DurableObjectStorage, 'put' | 'setAlarm'>) => Promise<T>): Promise<T> {
      return action(storage as unknown as Pick<DurableObjectStorage, 'put' | 'setAlarm'>);
    },
  };
  const connection = new Connection({ storage } as unknown as DurableObjectState, { ...env, CLOUDKIT_ENVIRONMENT: environment });
  const settings = () => values.get('connection') as { token: string; timeZone: string; zoneID: typeof zoneID; expiresAt?: number } | undefined;
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

function snapshot(records: unknown[], token: string, syncToken = 'end', moreComing = false) {
  return response({ zones: [{ zoneID, records, syncToken, moreComing }] }, token);
}

test('each deployment sends its own origin and CloudKit environment', async t => {
  const requests: { origin: string | null; path: string }[] = [];
  t.mock.method(globalThis, 'fetch', (input: unknown, init?: RequestInit) => {
    requests.push({ origin: new Headers(init?.headers).get('Origin'), path: new URL(String(input)).pathname });
    return response({ zones: [{ zoneID }] }, 'configured');
  });
  await setup('development').connection.configure('development-token', 'UTC');
  await setup('production').connection.configure('production-token', 'UTC');
  assert.deepEqual(requests.map(request => request.origin), ['https://mcp.development.nagare.page', 'https://mcp.nagare.page']);
  assert.match(requests[0].path, /\/development\/private\//);
  assert.match(requests[1].path, /\/production\/private\//);
});

test('overlapping calls wait for the preceding operation and persisted token rotation', async t => {
  const { connection, storage, settings } = setup();
  const saving = gate();
  const allowSave = gate();
  const tokens: (string | null)[] = [];
  intercept(t, url => {
    tokens.push(url.searchParams.get('ckWebAuthToken'));
    if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, 'token-1');
    return snapshot([project()], `token-${tokens.length}`);
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

test('selects the Core Data zone and filters its complete paginated snapshot', async t => {
  const { connection, values, settings } = setup();
  const markers: unknown[] = [];
  intercept(t, (url, body) => {
    if (url.pathname.endsWith('zones/list')) return response({ zones: [
      { zoneID: { zoneName: '_defaultZone' } }, { zoneID: { zoneName: 'unrelated' } }, { zoneID },
    ] }, 'signed-in');
    assert.ok(url.pathname.endsWith('changes/zone'));
    const [request] = body!.zones as { zoneID: typeof zoneID; syncToken?: string }[];
    assert.deepEqual(request.zoneID, zoneID);
    markers.push(request.syncToken);
    return request.syncToken === undefined
      ? snapshot([project(secondId, 'Second', 'z')], 'page-1-token', 'next-page', true)
      : snapshot([
        project(firstId, 'First', 'a'),
        { ...project(), recordName: 'other-type', recordType: 'CD_Todo' },
        { ...project(), recordName: 'other-entity', fields: { CD_entityName: { value: 'Other' } } },
      ], 'page-2-token');
  });
  await connection.configure('initial', 'America/Los_Angeles');
  const result = await connection.run({ name: 'list_projects' });
  assert.ok(result.ok);
  assert.deepEqual((result.data as { title: string }[]).map(item => item.title), ['First', 'Second']);
  assert.deepEqual(markers, [undefined, 'next-page']);
  assert.deepEqual(settings(), { token: 'page-2-token', timeZone: 'America/Los_Angeles', zoneID, expiresAt: settings()?.expiresAt });
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
    return snapshot([project(aliceRequest ? firstId : secondId, `${user}'s project`)], `${user}-rotated`);
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
    return snapshot([project()], 'recovered');
  });
  await connection.configure('initial', 'UTC');
  const failure = await connection.run({ name: 'list_projects' });
  assert.deepEqual(failure, { ok: false, code: 'THROTTLED', message: 'CloudKit could not complete the operation (THROTTLED).' });
  assert.ok(!JSON.stringify(failure).includes('private'));
  assert.equal((await connection.run({ name: 'list_projects' })).ok, true);
  assert.equal(settings()?.token, 'recovered');
});

for (const missingCode of ['NOT_FOUND', 'UNKNOWN_ITEM']) {
  test(`creates a task when exact lookup reports ${missingCode}`, async t => {
    const { connection } = setup();
    let writes = 0;
    intercept(t, (url, body) => {
      if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, 'configured');
      if (url.pathname.endsWith('records/lookup')) return response({ records: [{
        recordName: `CD_Todo_${firstId}`, serverErrorCode: missingCode,
      }] }, 'lookup-token');
      if (url.pathname.endsWith('changes/zone')) return snapshot([], 'snapshot-token');
      assert.ok(url.pathname.endsWith('records/modify'));
      const operations = body!.operations as { operationType: string; record: CloudKitRecord }[];
      assert.equal(operations.length, 1);
      assert.equal(operations[0].operationType, 'create');
      writes++;
      return response({ records: [{ ...operations[0].record, recordChangeTag: 'created' }] }, 'created-token');
    });
    await connection.configure('initial', 'UTC');
    const result = await connection.run({
      name: 'create_task', input: { id: firstId, title: 'New task', schedule: { date: '2026-10-01' } },
    });
    assert.ok(result.ok);
    assert.equal((result.data as { title: string }).title, 'New task');
    assert.equal(writes, 1);
  });
}

test('an exact-lookup permission failure blocks creation instead of treating the record as absent', async t => {
  const { connection } = setup();
  let requests = 0;
  intercept(t, url => {
    requests++;
    if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, 'configured');
    assert.ok(url.pathname.endsWith('records/lookup'));
    return response({ records: [{ recordName: `CD_Todo_${firstId}`, serverErrorCode: 'ACCESS_DENIED' }] }, 'lookup-token');
  });
  await connection.configure('initial', 'UTC');
  const result = await connection.run({
    name: 'create_task', input: { id: firstId, title: 'Must not create', schedule: { date: '2026-10-01' } },
  });
  assert.deepEqual(result, { ok: false, code: 'ACCESS_DENIED', message: 'CloudKit could not complete the operation (ACCESS_DENIED).' });
  assert.equal(requests, 2);
});

test('a create race refreshes the zone snapshot before resolving the winning record', async t => {
  const { connection } = setup();
  let winner: CloudKitRecord | undefined;
  let snapshots = 0;
  intercept(t, (url, body) => {
    if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, 'configured');
    if (url.pathname.endsWith('records/lookup')) return response({ records: [winner ?? {
      recordName: `CD_Todo_${firstId}`, serverErrorCode: 'NOT_FOUND',
    }] }, 'lookup-token');
    if (url.pathname.endsWith('changes/zone')) {
      snapshots++;
      return snapshot(winner ? [winner, project(secondId)] : [], 'snapshot-token');
    }
    assert.ok(url.pathname.endsWith('records/modify'));
    const [{ record }] = body!.operations as { record: CloudKitRecord }[];
    winner = { ...record, recordChangeTag: 'concurrent', fields: { ...record.fields,
      CD_title: { value: 'Concurrent winner' }, CD_project: { value: project(secondId).recordName },
    } };
    return response({ records: [{ recordName: record.recordName, serverErrorCode: 'ALREADY_EXISTS' }] }, 'race-token');
  });
  await connection.configure('initial', 'UTC');
  const result = await connection.run({ name: 'create_task', input: {
    id: firstId, title: 'Initial attempt', schedule: { date: '2026-10-02' },
  } });
  assert.ok(result.ok, JSON.stringify(result));
  const task = result.data as TaskInfo & { alreadyExists?: boolean };
  assert.equal(task.title, 'Concurrent winner');
  assert.equal(task.projectId, secondId);
  assert.equal(task.alreadyExists, true);
  assert.equal(snapshots, 2);
});

test('the connected transport supports projects, recurrence, history, and ordering in one workflow', async t => {
  const { connection, settings } = setup();
  t.mock.method(Date, 'now', () => Date.UTC(2026, 9, 2, 12));
  const records = new Map<string, CloudKitRecord>();
  let token = 'initial';
  let requests = 0;
  let writes = 0;
  let snapshots = 0;
  intercept(t, (url, body) => {
    assert.equal(url.searchParams.get('ckWebAuthToken'), token);
    token = `rotated-${++requests}`;
    if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, token);
    if (url.pathname.endsWith('changes/zone')) {
      assert.deepEqual(body, { zones: [{ zoneID }] });
      snapshots++;
      return snapshot([...records.values()], token);
    }
    assert.deepEqual(body?.zoneID, zoneID);
    if (url.pathname.endsWith('records/lookup')) {
      const requested = body!.records as { recordName: string }[];
      return response({ records: requested.map(({ recordName }) => records.get(recordName) ?? { recordName, serverErrorCode: 'NOT_FOUND' }) }, token);
    }
    assert.ok(url.pathname.endsWith('records/modify'));
    assert.equal(body!.atomic, true);
    const operations = body!.operations as { operationType: string; record: CloudKitRecord }[];
    for (const operation of operations) {
      const previous = records.get(operation.record.recordName);
      if (operation.operationType === 'create') assert.equal(previous, undefined);
      else assert.equal(operation.record.recordChangeTag, previous?.recordChangeTag);
    }
    writes++;
    return response({ records: operations.map(operation => {
      const previous = records.get(operation.record.recordName);
      if (operation.operationType === 'delete') {
        records.delete(operation.record.recordName);
        return { recordName: operation.record.recordName, deleted: true };
      }
      const saved = { ...operation.record, fields: { ...previous?.fields, ...operation.record.fields }, recordChangeTag: `revision-${writes}` };
      records.set(saved.recordName, saved);
      return saved;
    }) }, token);
  });
  await connection.configure('initial', 'UTC');
  const run = async <T>(operation: Operation): Promise<T> => {
    const before = snapshots;
    const result = await connection.run(operation);
    assert.ok(result.ok, JSON.stringify(result));
    assert.equal(snapshots - before, 1, `${operation.name} shares one fresh snapshot across record types`);
    return result.data as T;
  };
  type ProjectInfo = { id: string; title: string; prioritized: boolean; revision: string };
  type SeriesInfo = { id: string; title: string; revision: string; currentTaskId: string };
  const revision = (item: { revision?: string }) => { assert.ok(item.revision); return item.revision; };
  const taskId = '00000000-0000-0000-0000-000000000003';

  const first = await run<ProjectInfo>({ name: 'create_project', input: { id: firstId, title: 'First' } });
  const second = await run<ProjectInfo>({ name: 'create_project', input: { id: secondId, title: 'Second' } });
  const prioritized = await run<ProjectInfo>({ name: 'update_project', id: firstId, revision: first.revision, changes: { prioritized: true } });
  await run({ name: 'reorder_projects', input: { ids: [secondId], beforeId: firstId, revisions: { [secondId]: second.revision, [firstId]: prioritized.revision } } });
  const projects = await run<ProjectInfo[]>({ name: 'list_projects' });
  assert.deepEqual(projects.map(project => [project.id, project.prioritized]), [[secondId, true], [firstId, true]]);

  const created = await run<TaskInfo>({ name: 'create_task', input: {
    id: taskId, title: 'Daily task', projectId: firstId, schedule: { date: '2026-10-02' },
    recurrence: { mode: 'relative', unit: 'day', interval: 1 },
  } });
  assert.ok(created.recurrence);
  await run({ name: 'update_task', id: taskId, revision: revision(created), changes: { title: 'This occurrence', notes: 'Keep current notes' } });
  const [series] = await run<SeriesInfo[]>({ name: 'list_recurrences' });
  assert.equal(series.title, 'Daily task');
  await run({ name: 'update_recurrence', id: series.id, revision: series.revision, changes: { title: 'Future occurrence', projectId: secondId } });
  const writesBeforeRead = writes;
  const [today] = await run<TaskInfo[]>({ name: 'list_tasks', options: { date: 'today', projectId: secondId } });
  assert.equal(writes, writesBeforeRead);
  assert.equal(today.title, 'This occurrence');
  assert.equal(today.notes, 'Keep current notes');
  const [moved] = await run<TaskInfo[]>({ name: 'reorder_tasks', input: { ids: [taskId], date: '2026-10-03', revisions: { [taskId]: revision(today) } } });
  assert.equal(moved.date, '2026-10-03');
  await run({ name: 'complete_task', id: taskId, revision: revision(moved) });
  const [completed] = await run<TaskInfo[]>({ name: 'list_completed_tasks', options: { from: '2026-10-02', through: '2026-10-02' } });
  assert.equal(completed.id, taskId);
  assert.equal(completed.completedOn, '2026-10-02');
  const active = await run<TaskInfo[]>({ name: 'list_tasks', options: {} });
  assert.ok(active.every(task => task.id !== taskId));
  assert.ok(active.some(task => task.virtual));
  assert.equal(active.find(task => !task.virtual)!.title, 'Future occurrence');

  const reinstated = await run<TaskInfo>({ name: 'reinstate_task', id: taskId, revision: revision(completed) });
  assert.equal(reinstated.date, '2026-10-02');
  assert.equal(reinstated.recurrence, null);
  const [advanced] = await run<SeriesInfo[]>({ name: 'list_recurrences' });
  await run({ name: 'stop_recurrence', id: advanced.id, revision: advanced.revision });
  await run({ name: 'delete_task', id: taskId, revision: revision(reinstated) });
  await run({ name: 'delete_project', id: secondId, revision: projects[0].revision });
  const [remaining] = await run<TaskInfo[]>({ name: 'list_tasks', options: {} });
  assert.equal(remaining.title, 'Future occurrence');
  assert.equal(remaining.recurrence, null);
  assert.equal(remaining.projectId, null);
  assert.deepEqual(await run({ name: 'list_recurrences' }), []);
  assert.equal(settings()?.token, token);
});

test('only configuration and successful operations extend the 30-day idle deadline', async t => {
  const { connection, storage, settings } = setup();
  const month = 30 * 24 * 60 * 60 * 1000;
  let now = Date.UTC(2026, 9, 1);
  t.mock.method(Date, 'now', () => now);
  let fail = true;
  intercept(t, url => {
    if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, 'configured');
    if (fail) return Response.json({ serverErrorCode: 'THROTTLED' }, { status: 429 });
    return snapshot([project()], 'used');
  });
  await connection.configure('initial', 'UTC');
  const originalDeadline = now + month;
  assert.equal(settings()?.expiresAt, originalDeadline);
  assert.equal(storage.alarmAt, originalDeadline);
  now += 86_400_000;
  assert.equal((await connection.run({ name: 'list_projects' })).ok, false);
  assert.equal(settings()?.expiresAt, originalDeadline);
  assert.equal(storage.alarmAt, originalDeadline);
  fail = false;
  assert.equal((await connection.run({ name: 'list_projects' })).ok, true);
  assert.equal(settings()?.expiresAt, now + month);
  assert.equal(storage.alarmAt, now + month);
});

test('legacy credentials without an idle deadline require reconnection before contacting CloudKit', async t => {
  const { connection, values } = setup();
  values.set('connection', { token: 'legacy-token', timeZone: 'UTC', zoneID });
  intercept(t, () => { assert.fail('Expired credentials must not be sent to CloudKit.'); });
  assert.deepEqual(await connection.run({ name: 'list_projects' }), {
    ok: false, code: 'AUTHENTICATION_REQUIRED', message: 'Reconnect Nagare to your agent.',
  });
  assert.equal(values.size, 0);
});

for (const trigger of ['run', 'alarm'] as const) {
  test(`${trigger} removes expired credentials and alarms without contacting CloudKit`, async t => {
    const { connection, values, storage, settings } = setup();
    let now = Date.UTC(2026, 9, 1);
    t.mock.method(Date, 'now', () => now);
    let requests = 0;
    intercept(t, () => { requests++; return response({ zones: [{ zoneID }] }, 'configured'); });
    await connection.configure('initial', 'UTC');
    now = settings()!.expiresAt!;
    if (trigger === 'alarm') await connection.alarm();
    const result = await connection.run({ name: 'list_projects' });
    assert.deepEqual(result, { ok: false, code: 'AUTHENTICATION_REQUIRED', message: 'Reconnect Nagare to your agent.' });
    assert.equal(requests, 1);
    assert.equal(values.size, 0);
    assert.equal(storage.alarmAt, null);
  });
}

for (const activity of ['configure', 'run'] as const) {
  test(`a delayed alarm cannot delete credentials refreshed by an in-flight ${activity}`, async t => {
    const { connection, storage, settings } = setup();
    let now = Date.UTC(2026, 9, 1);
    t.mock.method(Date, 'now', () => now);
    const started = gate();
    const release = gate();
    let delay = false;
    intercept(t, async url => {
      if (delay) { started.open(); await release.promise; }
      return url.pathname.endsWith('zones/list') ? response({ zones: [{ zoneID }] }, 'current-token') : snapshot([project()], 'current-token');
    });
    await connection.configure('initial', 'UTC');
    const oldDeadline = settings()!.expiresAt!;
    now = oldDeadline - 1;
    delay = true;
    const operation = activity === 'configure' ? connection.configure('new-sign-in', 'UTC') : connection.run({ name: 'list_projects' });
    await started.promise;
    now = oldDeadline + 1;
    const alarm = connection.alarm();
    release.open();
    await Promise.all([operation, alarm]);
    assert.equal(settings()?.token, 'current-token');
    assert.ok(settings()!.expiresAt! > now);
    assert.equal(storage.alarmAt, settings()?.expiresAt);
  });
}

test('ordinary reads do not download unrelated completed notes; history loads them only when requested', async t => {
  const { connection } = setup();
  const now = Date.now();
  const todo = (id: string, completed: boolean): CloudKitRecord => ({
    recordType: 'CD_Todo', recordName: id, recordChangeTag: 'v1', fields: {
      CD_entityName: { value: 'Todo' }, CD_id: { value: id }, CD_title: { value: completed ? 'History' : 'Active' },
      CD_order: { value: id }, CD_scheduledDate: { value: now }, CD_createdAt: { value: now },
      CD_completedAt: { value: completed ? now : null },
      ...(completed ? { CD_notes_ckAsset: { value: { downloadURL: 'https://cvws.icloud-content.com/history', size: 20 } } } : {}),
    },
  });
  const active = todo(secondId, false);
  const history = todo('00000000-0000-0000-0000-000000000003', true);
  active.fields.CD_order = { value: 'i' };
  history.fields.CD_order = { value: 'r' };
  let downloads = 0;
  intercept(t, url => {
    if (url.hostname !== 'api.apple-cloudkit.com') { downloads++; return new Response(null, { status: 503 }); }
    if (url.pathname.endsWith('zones/list')) return response({ zones: [{ zoneID }] }, 'configured');
    return snapshot([project(), active, history], 'read');
  });
  await connection.configure('initial', 'America/Los_Angeles');
  assert.equal((await connection.run({ name: 'list_projects' })).ok, true);
  const tasks = await connection.run({ name: 'list_tasks', options: {} });
  assert.equal(tasks.ok, true);
  assert.deepEqual(tasks.ok && (tasks.data as TaskInfo[]).map(task => task.title), ['Active']);
  assert.equal(downloads, 0);
  assert.deepEqual(await connection.run({ name: 'list_completed_tasks', options: {} }), {
    ok: false, code: 'ASSET_HTTP_ERROR', message: 'CloudKit could not complete the operation (ASSET_HTTP_ERROR).',
  });
  assert.equal(downloads, 1);
});
