import assert from 'node:assert/strict';
import test from 'node:test';
import { CloudKitError, type CloudKitRecord, type CloudKitValue } from '../src/cloudkit.js';
import { Projects } from '../src/projects.js';
import { NagareError, type Mutation, type RecordType, type Store } from '../src/records.js';

const A = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA';
const B = 'BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB';
const C = 'CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC';
const D = 'DDDDDDDD-DDDD-4DDD-8DDD-DDDDDDDDDDDD';
const TASK = '11111111-1111-4111-8111-111111111111';
const DONE = '22222222-2222-4222-8222-222222222222';
const TEMPLATE = '33333333-3333-4333-8333-333333333333';
const NOW = Date.parse('2026-10-02T19:00:00Z');

function record(recordType: RecordType, id: string, fields: Record<string, CloudKitValue> = {}): CloudKitRecord {
  return {
    recordType, recordName: `cloud-${id}`, recordChangeTag: 'v1',
    fields: Object.fromEntries(Object.entries({ id, title: id, order: 'i', priorityRawValue: 1, ...fields })
      .map(([key, value]) => [`CD_${key}`, { value }])),
  };
}

class MemoryStore implements Store {
  records: CloudKitRecord[];
  batches: Mutation[][] = [];
  beforeModify?: () => void;
  constructor(...records: CloudKitRecord[]) { this.records = structuredClone(records); }
  async list(type: RecordType) { return structuredClone(this.records.filter(record => record.recordType === type)); }
  async lookup(name: string) { return structuredClone(this.records.find(record => record.recordName === name)); }
  async modify(operations: Mutation[]) {
    this.beforeModify?.();
    for (const operation of operations) {
      const existing = this.records.find(record => record.recordName === operation.record.recordName);
      if (operation.operationType === 'create') {
        if (existing) throw new CloudKitError('ALREADY_EXISTS');
      } else if (!existing || existing.recordChangeTag !== operation.record.recordChangeTag) {
        throw new CloudKitError('CONFLICT');
      }
    }
    this.batches.push(structuredClone(operations));
    const results: CloudKitRecord[] = [];
    for (const operation of operations) {
      const existing = this.records.find(record => record.recordName === operation.record.recordName);
      this.records = this.records.filter(record => record.recordName !== operation.record.recordName);
      if (operation.operationType !== 'delete') {
        const saved = { ...operation.record, fields: { ...existing?.fields, ...operation.record.fields }, recordChangeTag: `v${this.batches.length + 1}` };
        this.records.push(saved);
        results.push(structuredClone(saved));
      }
    }
    return results;
  }
}

function setup(...records: CloudKitRecord[]) {
  const store = new MemoryStore(...records);
  return { store, projects: new Projects(store, () => NOW) };
}

const code = (expected: string) => (error: unknown) => error instanceof NagareError && error.code === expected;

test('lists native priority groups and legacy priority values with editable revisions', async () => {
  const { projects } = setup(
    record('CD_Project', A, { order: 'a' }),
    record('CD_Project', B, { order: 'z', priorityRawValue: 2 }),
    record('CD_Project', C, { order: 'b', priorityRawValue: 0, isPriority: 1 }),
    record('CD_Project', D, { order: 'i', priorityRawValue: null, isPriority: 1 }),
  );
  const result = await projects.list();
  assert.deepEqual(result.map(item => item.id), [D, B, A, C]);
  assert.deepEqual(result.map(item => item.prioritized), [true, true, false, false]);
  assert.ok(result.every(item => item.revision === 'v1'));
});

test('creates at the end of its priority group and retries preserve later edits', async () => {
  const { store, projects } = setup(record('CD_Project', A, { order: 'i' }), record('CD_Project', B, { order: 'z', priorityRawValue: 2 }));
  const created = await projects.create({ id: C.toLowerCase(), title: 'New project', notes: 'Keep me' });
  const saved = store.records.find(record => record.fields.CD_id.value === C)!;
  assert.equal(saved.fields.CD_order.value, 'r');
  assert.equal(saved.fields.CD_priorityRawValue.value, 1);
  assert.equal(saved.fields.CD_isPriority.value, 0);
  assert.equal(saved.fields.CD_createdAt.value, NOW);
  assert.ok(saved.fields.CD_syncRecordID.value);
  const edited = await projects.update(C, { title: 'Edited natively', notes: 'New notes' }, created.revision!);
  const retried = await projects.create({ id: C, title: 'Stale initial title', notes: 'Stale notes' });
  assert.deepEqual(retried, { ...edited, alreadyExists: true });
  assert.equal(store.batches.length, 2);
});

test('a concurrent create with the same ID is returned without overwriting it', async () => {
  const { store, projects } = setup();
  store.beforeModify = () => {
    const concurrent = record('CD_Project', A, { title: 'Created on another device' });
    concurrent.recordName = `CD_Project_${A}`;
    store.records.push(concurrent);
    store.beforeModify = undefined;
  };
  const result = await projects.create({ id: A, title: 'Original request' });
  assert.equal(result.title, 'Created on another device');
  assert.equal('alreadyExists' in result && result.alreadyExists, true);
  assert.equal(store.batches.length, 0);
});

test('promotion appends and demotion prepends just like the native swipe', async () => {
  const { projects } = setup(
    record('CD_Project', A, { order: 'a' }),
    record('CD_Project', B, { order: 'i' }),
    record('CD_Project', C, { order: 'z', priorityRawValue: 2 }),
  );
  const promoted = await projects.update(B, { prioritized: true }, 'v1');
  assert.deepEqual((await projects.list()).map(item => item.id), [C, B, A]);
  await projects.update(B, { prioritized: false }, promoted.revision!);
  assert.deepEqual((await projects.list()).map(item => item.id), [C, B, A]);
  assert.deepEqual((await projects.list()).map(item => item.prioritized), [true, false, false]);
});

test('text patches preserve the other text field, metadata, and ordering', async () => {
  const { store, projects } = setup(record('CD_Project', A, {
    title: 'Fresh title', notes: 'Original notes', notes_ckAsset: { downloadURL: 'https://example.invalid/asset' },
    order: 'j', createdAt: 100, syncRecordID: B,
  }));
  const result = await projects.update(A, { notes: 'Updated notes' }, 'v1');
  assert.equal(result.title, 'Fresh title');
  const fields = store.batches[0][0].record.fields;
  assert.deepEqual(Object.keys(fields).sort(), ['CD_modifiedAt', 'CD_notes', 'CD_notes_ckAsset']);
  assert.equal(fields.CD_notes_ckAsset.value, null);
  assert.equal(store.records[0].fields.CD_createdAt.value, 100);
  assert.equal(store.records[0].fields.CD_order.value, 'j');
});

test('moves a block across priority groups in the requested order using fractional keys', async () => {
  const { store, projects } = setup(
    record('CD_Project', A, { order: 'i', priorityRawValue: 2 }),
    record('CD_Project', B, { order: 'a' }),
    record('CD_Project', C, { order: 'b' }),
    record('CD_Project', D, { order: 'z' }),
  );
  const result = await projects.reorder({ ids: [C, B], beforeId: A, revisions: { [B]: 'v1', [C]: 'v1', [A]: 'v1' } });
  assert.deepEqual(result.map(item => item.id), [C, B, A, D]);
  assert.deepEqual(result.map(item => item.prioritized), [true, true, true, false]);
  assert.equal(store.batches[0].length, 2);
  assert.ok(store.batches[0].every(operation => operation.record.recordChangeTag === 'v1'));
});

test('stale project revisions and invalid destinations fail before a write', async () => {
  const { store, projects } = setup(record('CD_Project', A), record('CD_Project', B));
  await assert.rejects(projects.update(A, { notes: 'Overwrite' }, 'stale'), code('CONFLICT'));
  await assert.rejects(projects.reorder({ ids: [A], beforeId: B, revisions: {} }), code('CONFLICT'));
  await assert.rejects(projects.reorder({ ids: [A], beforeId: B, revisions: { [A]: 'v1', [B]: 'stale' } }), code('CONFLICT'));
  await assert.rejects(projects.reorder({ ids: [A], beforeId: A, revisions: { [A]: 'v1' } }), code('INVALID_MOVE'));
  assert.equal(store.batches.length, 0);
});

test('deleting a project detaches active, completed, and recurring items without deleting their content', async () => {
  const parent = record('CD_Project', A);
  const todo = record('CD_Todo', TASK, { title: 'Keep task', project: parent.recordName, projectOrder: 'j', recurrenceTemplate: `cloud-${TEMPLATE}` });
  const done = record('CD_Todo', DONE, { notes: 'Keep history', completedAt: 100, project: parent.recordName, projectOrder: 'k' });
  const template = record('CD_RecurrenceTemplate', TEMPLATE, { title: 'Keep repeat', project: parent.recordName, currentItemID: TASK });
  const unrelated = record('CD_Project', B);
  const { store, projects } = setup(parent, todo, done, template, unrelated);
  assert.deepEqual(await projects.delete(A, 'v1'), { id: A, deleted: true });
  assert.equal(store.records.length, 4);
  for (const child of store.records.filter(record => record.recordType !== 'CD_Project')) {
    assert.equal(child.fields.CD_project.value, null);
    assert.equal(child.fields.CD_modifiedAt.value, NOW);
    if (child.recordType === 'CD_Todo') assert.equal(child.fields.CD_projectOrder.value, null);
  }
  assert.equal(store.records.find(record => record.recordName === todo.recordName)!.fields.CD_recurrenceTemplate.value, `cloud-${TEMPLATE}`);
  assert.equal(store.records.find(record => record.recordName === done.recordName)!.fields.CD_completedAt.value, 100);
  assert.deepEqual(store.records.find(record => record.recordName === unrelated.recordName), unrelated);
  assert.equal(store.batches.length, 1);
  assert.ok(store.batches[0].every(operation => operation.record.recordChangeTag === 'v1'));
});

test('concurrent child edits abort the whole project deletion', async () => {
  const parent = record('CD_Project', A);
  const child = record('CD_Todo', TASK, { project: parent.recordName, projectOrder: 'j' });
  const { store, projects } = setup(parent, child);
  store.beforeModify = () => { store.records[1].recordChangeTag = 'concurrent'; };
  await assert.rejects(projects.delete(A, 'v1'), (error: unknown) => error instanceof CloudKitError && error.code === 'CONFLICT');
  assert.equal(store.records.length, 2);
  assert.equal(store.records[1].fields.CD_project.value, parent.recordName);
  assert.equal(store.batches.length, 0);
});

test('rebalancing a damaged order protects every repaired project against concurrent edits', async () => {
  const { store, projects } = setup(record('CD_Project', A, { order: '' }), record('CD_Project', B, { order: 'i' }));
  store.beforeModify = () => { store.records[0].recordChangeTag = 'concurrent'; };
  await assert.rejects(projects.reorder({ ids: [B], beforeId: A, revisions: { [B]: 'v1' } }),
    (error: unknown) => error instanceof CloudKitError && error.code === 'CONFLICT');
  assert.equal(store.batches.length, 0);
  assert.equal(store.records[1].fields.CD_order.value, 'i');
});
