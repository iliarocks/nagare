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
    return json({ userRecordName: 'user-1', nameComponents: { givenName: 'Private' } });
  });
  assert.deepEqual(await client.currentUser(), { userRecordName: 'user-1' });
});

test('rejects missing or malformed caller identities', async () => {
  for (const userRecordName of [undefined, null, '', 42, {}]) {
    const client = mockClient(() => json({ userRecordName }));
    await assert.rejects(client.currentUser(), { code: 'UNEXPECTED_SERVER_RESPONSE' });
  }
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
      zoneID, atomic: true, operations: [{ operationType: 'update', record: {
        ...patch, fields: { ...patch.fields, CD_title_ckAsset: { value: null } },
      } }],
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

const assetURL = 'https://cvws.icloud-content.com/B/test/notes?signature=private-signature';
const assetRecord = (text: string, url = assetURL): CloudKitRecord => ({
  ...record,
  fields: { ...record.fields, CD_notes: { value: null }, CD_notes_ckAsset: {
    value: { downloadURL: url, size: new TextEncoder().encode(text).byteLength }, type: 'ASSET',
  } },
});

test('hydrates snapshot text assets as UTF-8 without leaking API credentials or accepting asset token headers', async () => {
  const text = '\uFEFF日本語 café 😀\nSecond line';
  const bytes = new TextEncoder().encode(text);
  const persisted: string[] = [];
  const client = mockClient((url, init) => {
    if (url.hostname === 'api.apple-cloudkit.com') return json({ zones: [{ zoneID, records: [assetRecord(text)], moreComing: false }] });
    assert.equal(url.href, assetURL);
    assert.equal(init.method, 'GET');
    assert.equal(init.redirect, 'manual');
    assert.equal(init.headers, undefined);
    assert.equal(url.searchParams.has('ckAPIToken'), false);
    assert.equal(url.searchParams.has('ckWebAuthToken'), false);
    // Split a multibyte code point across network chunks.
    return new Response(new ReadableStream({ start(controller) {
      controller.enqueue(bytes.slice(0, 4));
      controller.enqueue(bytes.slice(4));
      controller.close();
    } }), { headers: { 'x-apple-cloudkit-session': 'must-not-persist' } });
  }, { origin: 'https://mcp.example', onWebAuthToken: token => { persisted.push(token); } });
  const result = await client.hydrate(await client.snapshot(zoneID));
  assert.equal(result[0].fields.CD_notes.value, text);
  assert.deepEqual(result[0].fields.CD_notes_ckAsset, { value: null });
  assert.deepEqual(persisted, []);
});

test('lookup hydrates an empty asset and honors present inline text, including empty text, over stale assets', async () => {
  let downloads = 0;
  const client = mockClient(url => {
    if (url.hostname === 'api.apple-cloudkit.com') return json({ records: [
      assetRecord(''),
      { ...assetRecord('ignored'), recordName: 'inline', fields: { ...assetRecord('ignored').fields, CD_notes: { value: 'Current inline text' } } },
      { ...assetRecord('ignored'), recordName: 'empty-inline', fields: { ...assetRecord('ignored').fields, CD_notes: { value: '' } } },
    ] });
    downloads++;
    return new Response('');
  });
  const records = await client.lookup({ zoneID, recordNames: [record.recordName, 'inline', 'empty-inline'] });
  assert.equal(records[0].fields.CD_notes.value, '');
  assert.equal(records[1].fields.CD_notes.value, 'Current inline text');
  assert.equal(records[2].fields.CD_notes.value, '');
  assert.equal(records[2].fields.CD_notes_ckAsset.value, null);
  assert.equal(downloads, 1);
});

test('uploads large UTF-8 text through signed URLs before atomically saving the receipt and clearing inline text', async () => {
  const text = 'こんにちは😀'.repeat(30_000);
  const receipt = { wrappingKey: 'wrapping', fileChecksum: 'checksum', receipt: 'receipt', referenceChecksum: 'reference', size: new TextEncoder().encode(text).length };
  const calls: string[] = [];
  const client = mockClient(async (url, init) => {
    calls.push(url.pathname);
    if (url.pathname.endsWith('/assets/upload')) {
      assert.deepEqual(JSON.parse(String(init.body)), { zoneID, tokens: [{
        recordName: record.recordName, recordType: record.recordType, fieldName: 'CD_notes_ckAsset',
      }] });
      return json({ tokens: [{ recordName: record.recordName, fieldName: 'CD_notes_ckAsset', url: assetURL }] }, {
        headers: { 'x-apple-cloudkit-web-auth-token': 'rotated-for-modify' },
      });
    }
    if (url.hostname === 'cvws.icloud-content.com') {
      assert.equal(init.method, 'POST');
      assert.equal(init.headers, undefined);
      assert.ok(init.body instanceof Blob);
      assert.equal(await init.body.text(), text);
      return json({ singleFile: receipt });
    }
    assert.ok(url.pathname.endsWith('/records/modify'));
    assert.equal(url.searchParams.get('ckWebAuthToken'), 'rotated-for-modify');
    const body = JSON.parse(String(init.body));
    assert.equal(body.atomic, true);
    assert.deepEqual(body.operations[0].record.fields, {
      CD_notes: { value: null }, CD_notes_ckAsset: { value: receipt },
    });
    // CloudKit omits the removed inline field; Core Data can then import the asset.
    return json({ records: [{ ...record, recordChangeTag: 'updated', fields: { CD_notes_ckAsset: { value: receipt } } }] });
  }, { origin: 'https://mcp.example' });
  const patch = { ...record, fields: { CD_notes: { value: text }, CD_notes_ckAsset: { value: null } } };
  const saved = await client.modify({ zoneID, operations: [{ operationType: 'update', record: patch }] });
  assert.equal(saved[0].fields.CD_notes.value, text);
  assert.equal(saved[0].recordChangeTag, 'updated');
  assert.equal(patch.fields.CD_notes.value, text);
  assert.equal(calls.length, 3);
});

test('short, empty, and null text replacements clear existing assets without uploading or changing unrelated fields', async () => {
  for (const value of ['Short replacement', '', null]) {
    const client = mockClient((url, init) => {
      assert.ok(url.pathname.endsWith('/records/modify'));
      const body = JSON.parse(String(init.body));
      assert.deepEqual(body.operations[0].record.fields, { CD_notes: { value }, CD_notes_ckAsset: { value: null } });
      return json({ records: [{ ...record, fields: body.operations[0].record.fields }] });
    });
    await client.modify({ zoneID, operations: [{ operationType: 'update', record: { ...record, fields: { CD_notes: { value } } } }] });
  }
});

test('raw fetched assets cannot accidentally clear stored text, and fail before any upload or write', async () => {
  let calls = 0;
  const client = mockClient(() => { calls++; throw new Error('Unexpected request'); });
  const fetched = assetRecord('Existing notes');
  await assert.rejects(client.modify({ zoneID, operations: [
    { operationType: 'create', record: { ...record, recordName: 'new', fields: { CD_notes: { value: 'large text'.repeat(30_000) } } } },
    { operationType: 'update', record: fetched },
  ] }), { code: 'READ_ONLY_ASSET' });
  assert.equal(calls, 0);
  assert.equal(fetched.fields.CD_notes.value, null);
  assert.equal((fetched.fields.CD_notes_ckAsset.value as { downloadURL: string }).downloadURL, assetURL);
});

test('an explicit uploaded asset receipt with null inline text remains writable', async () => {
  const receipt = { wrappingKey: 'wrapping', fileChecksum: 'checksum', receipt: 'receipt', referenceChecksum: 'reference', size: 14 };
  const fields = { CD_notes: { value: null }, CD_notes_ckAsset: { value: receipt } };
  const client = mockClient((url, init) => {
    assert.ok(url.pathname.endsWith('/records/modify'));
    assert.deepEqual(JSON.parse(String(init.body)).operations[0].record.fields, fields);
    return json({ records: [{ ...record, fields, recordChangeTag: 'updated' }] });
  });
  const [saved] = await client.modify({ zoneID, operations: [{ operationType: 'update', record: { ...record, fields } }] });
  assert.equal(saved.recordChangeTag, 'updated');
  assert.deepEqual(saved.fields, fields);
});

test('rejects untrusted asset destinations and asset redirects before exposing credentials or following them', async () => {
  for (const destination of ['http://cvws.icloud-content.com/file', 'https://cvws.icloud-content.com.evil.test/file', 'https://user:password@cvws.icloud-content.com/file', 'https://cvws.icloud-content.com:444/file', 'https://127.0.0.1/private']) {
    let calls = 0;
    const client = mockClient(() => { calls++; return json({ records: [assetRecord('text', destination)] }); });
    await assert.rejects(client.lookup({ zoneID, recordNames: [record.recordName] }), { code: 'INVALID_ASSET_URL' });
    assert.equal(calls, 1);
  }
  let calls = 0;
  const redirect = mockClient(url => {
    calls++;
    return url.hostname === 'api.apple-cloudkit.com' ? json({ records: [assetRecord('text')] })
      : new Response(null, { status: 302, headers: { Location: 'https://evil.example/private-signature' } });
  });
  await assert.rejects(redirect.lookup({ zoneID, recordNames: [record.recordName] }), { code: 'UNEXPECTED_REDIRECT' });
  assert.equal(calls, 2);
});

test('rejects corrupt, truncated, and failed assets without disclosing signed URLs or bodies', async () => {
  for (const [response, code] of [
    [new Response(new Uint8Array([0xff, 0xff, 0xff, 0xff])), 'INVALID_TEXT_ASSET'],
    [new Response('cut'), 'ASSET_SIZE_MISMATCH'],
    [new Response('private server detail', { status: 403 }), 'ASSET_HTTP_ERROR'],
  ] as const) {
    const client = mockClient(url => url.hostname === 'api.apple-cloudkit.com' ? json({ records: [assetRecord('text')] }) : response);
    await assert.rejects(client.lookup({ zoneID, recordNames: [record.recordName] }), error => {
      assert.ok(error instanceof CloudKitError);
      assert.equal(error.code, code);
      assert.ok(!String(error).includes('private'));
      return true;
    });
  }
});

test('does not save a record when asset upload fails or supplies a mismatched upload token', async () => {
  for (const mismatch of [false, true]) {
    let requests = 0;
    const client = mockClient(url => {
      requests++;
      assert.ok(!url.pathname.endsWith('/records/modify'));
      if (url.pathname.endsWith('/assets/upload')) return json({ tokens: [{
        recordName: mismatch ? 'another-record' : record.recordName, fieldName: 'CD_notes_ckAsset', url: assetURL,
      }] });
      throw new Error(`Request failed at ${url}`);
    });
    await assert.rejects(client.modify({ zoneID, operations: [{ operationType: 'update', record: {
      ...record, fields: { CD_notes: { value: 'long text'.repeat(30_000) } },
    } }] }), error => {
      assert.ok(error instanceof CloudKitError);
      assert.equal(error.code, mismatch ? 'UNEXPECTED_SERVER_RESPONSE' : 'NETWORK_ERROR');
      assert.ok(!String(error).includes('private-signature'));
      return true;
    });
    assert.equal(requests, mismatch ? 1 : 2);
  }
});

test('deletes use optimistic concurrency and atomic batches, returning only surviving records', async () => {
  const deleted = { ...assetRecord('unused'), recordName: 'delete-me' };
  const client = mockClient((url, init) => {
    assert.ok(url.pathname.endsWith('/records/modify'));
    const body = JSON.parse(String(init.body));
    assert.equal(body.atomic, true);
    assert.deepEqual(body.operations[0], { operationType: 'delete', record: { recordName: 'delete-me', recordChangeTag: record.recordChangeTag } });
    return json({ records: [{ recordName: 'delete-me', deleted: true }, record] });
  });
  assert.deepEqual(await client.modify({ zoneID, operations: [
    { operationType: 'delete', record: deleted }, { operationType: 'update', record },
  ] }), [record]);
  const noTag = mockClient(() => { throw new Error('Must not fetch'); });
  await assert.rejects(noTag.modify({ zoneID, operations: [{ operationType: 'delete', record: { ...deleted, recordChangeTag: undefined } }] }), {
    code: 'MISSING_RECORD_CHANGE_TAG',
  });
});

test('delete conflicts and missing acknowledgements fail closed without retrying', async () => {
  for (const records of [[], [{ recordName: 'other', deleted: true }], [record], [{ recordName: record.recordName, serverErrorCode: 'CONFLICT' }]]) {
    let requests = 0;
    const client = mockClient(() => { requests++; return json({ records }); });
    await assert.rejects(client.modify({ zoneID, operations: [{ operationType: 'delete', record }] }), {
      code: records[0] && 'serverErrorCode' in records[0] ? 'CONFLICT' : 'UNEXPECTED_SERVER_RESPONSE',
    });
    assert.equal(requests, 1);
  }
});

test('a zone snapshot folds paginated updates, deletions and recreation, then hydrates only surviving assets', async () => {
  const latest = { ...record, recordChangeTag: 'latest', fields: { CD_title: { value: 'Newest title' } } };
  const deletedAsset = { ...assetRecord('obsolete'), recordName: 'deleted-asset' };
  const updatedAsset = { ...assetRecord('obsolete', 'https://untrusted.example/old'), recordName: 'updated' };
  const project = { ...record, recordName: 'project', recordType: 'CD_Project' };
  const revived = { ...assetRecord('Current notes'), recordName: 'revived' };
  const pages = [
    { records: [record, project, deletedAsset, updatedAsset, { recordName: 'revived', deleted: true }], syncToken: 'page-one', moreComing: true },
    { records: [latest, { recordName: 'deleted-asset', deleted: true }, { ...latest, recordName: 'updated' }, revived], syncToken: 'finished', moreComing: false },
  ];
  let page = 0;
  const assetRequests: string[] = [];
  const client = mockClient((url, init) => {
    if (url.hostname !== 'api.apple-cloudkit.com') {
      assetRequests.push(url.href);
      return new Response('Current notes');
    }
    assert.ok(url.pathname.endsWith('/private/changes/zone'));
    assert.deepEqual(JSON.parse(String(init.body)), { zones: [{ zoneID, ...(page ? { syncToken: 'page-one' } : {}) }] });
    assert.equal(url.searchParams.get('ckWebAuthToken'), page ? 'rotated-during-sync' : base.webAuthToken);
    return json({ zones: [{ zoneID, ...pages[page++] }] }, { headers: { 'x-apple-cloudkit-session': 'rotated-during-sync' } });
  });
  const snapshot = await client.snapshot(zoneID);
  assert.deepEqual(assetRequests, []);
  await client.hydrate(snapshot);
  assert.equal(page, 2);
  assert.equal(snapshot.length, 4);
  assert.equal(snapshot.find(item => item.recordName === record.recordName)?.recordChangeTag, 'latest');
  assert.equal(snapshot.find(item => item.recordName === record.recordName)?.fields.CD_scheduledDate, undefined);
  assert.equal(snapshot.find(item => item.recordName === 'project')?.recordType, 'CD_Project');
  assert.equal(snapshot.find(item => item.recordName === 'revived')?.fields.CD_notes.value, 'Current notes');
  assert.equal(snapshot.find(item => item.recordName === 'deleted-asset'), undefined);
  assert.deepEqual(assetRequests, [assetURL]);
});

test('each snapshot starts from an empty cursor so completed initial sync state cannot hide later additions or deletions', async () => {
  let calls = 0;
  const client = mockClient((_url, init) => {
    assert.deepEqual(JSON.parse(String(init.body)), { zones: [{ zoneID }] });
    return json({ zones: [{ zoneID, records: calls++ === 0 ? [record] : [], moreComing: false, syncToken: 'not-reused' }] });
  });
  assert.equal((await client.snapshot(zoneID)).length, 1);
  assert.deepEqual(await client.snapshot(zoneID), []);
  assert.equal(calls, 2);
});

test('a snapshot rejects partial zone or record failures instead of returning an incomplete task set', async () => {
  const bodies = [
    { zones: [{ zoneID, serverErrorCode: 'ZONE_NOT_FOUND', reason: 'private zone details' }] },
    { zones: [{ zoneID, records: [record, { recordName: 'unreadable', serverErrorCode: 'ACCESS_DENIED', reason: 'private record details' }], moreComing: false }] },
  ];
  for (const [index, body] of bodies.entries()) {
    const client = mockClient(() => json(body));
    await assert.rejects(client.snapshot(zoneID), error => {
      assert.ok(error instanceof CloudKitError);
      assert.equal(error.code, index ? 'ACCESS_DENIED' : 'ZONE_NOT_FOUND');
      assert.ok(!String(error).includes('private'));
      return true;
    });
  }
});

test('snapshot pagination rejects a missing or repeated cursor, an unexpected zone, and malformed page contents', async () => {
  const invalidPages = [
    { zoneID, records: [record], moreComing: true },
    { zoneID: { zoneName: 'another-zone' }, records: [record], moreComing: false },
    { zoneID, records: null, moreComing: false },
    { zoneID, records: [null], moreComing: false },
    { zoneID, records: [{ recordName: 'broken', recordType: 'CD_Todo' }], moreComing: false },
    { zoneID, records: [], moreComing: 'false' },
  ];
  for (const page of invalidPages) {
    const client = mockClient(() => json({ zones: [page] }));
    await assert.rejects(client.snapshot(zoneID), { code: 'UNEXPECTED_SERVER_RESPONSE' });
  }
  let calls = 0;
  const stuck = mockClient(() => {
    calls++;
    return json({ zones: [{ zoneID, records: [record], moreComing: true, syncToken: 'stuck' }] });
  });
  await assert.rejects(stuck.snapshot(zoneID), { code: 'UNEXPECTED_SERVER_RESPONSE' });
  assert.equal(calls, 2);
});

test('a successful edit returns its acknowledged patch without downloading unchanged assets again', async () => {
  let downloads = 0;
  const original = assetRecord('Large notes already read');
  const client = mockClient((url, init) => {
    if (url.hostname !== 'api.apple-cloudkit.com') {
      downloads++;
      if (downloads > 1) throw new Error('Asset unavailable after save');
      return new Response('Large notes already read');
    }
    if (url.pathname.endsWith('/changes/zone')) return json({ zones: [{ zoneID, records: [original], moreComing: false }] });
    assert.ok(url.pathname.endsWith('/records/modify'));
    assert.equal(JSON.parse(String(init.body)).operations[0].record.fields.CD_title.value, 'Renamed');
    return json({ records: [{ ...original, recordChangeTag: 'committed', fields: { ...original.fields, CD_title: { value: 'Renamed' } } }] });
  });
  const [before] = await client.hydrate(await client.snapshot(zoneID));
  assert.equal(before.fields.CD_notes.value, 'Large notes already read');
  const [saved] = await client.modify({ zoneID, operations: [{ operationType: 'update', record: {
    ...before, fields: { CD_title: { value: 'Renamed' } },
  } }] });
  assert.equal(saved.recordChangeTag, 'committed');
  assert.deepEqual(saved.fields, { CD_title: { value: 'Renamed' } });
  assert.equal(downloads, 1);
});

test('oversized atomic transactions are rejected before any asset upload or record request', async () => {
  let calls = 0;
  const client = mockClient(() => { calls++; throw new Error('Must not fetch'); });
  await assert.rejects(client.modify({ zoneID, operations: Array.from({ length: 201 }, (_, index) => ({
    operationType: 'create', record: { ...record, recordName: `new-${index}`, fields: { CD_notes: { value: 'large text'.repeat(30_000) } } },
  })) }), { code: 'TRANSACTION_TOO_LARGE' });
  assert.equal(calls, 0);
});
