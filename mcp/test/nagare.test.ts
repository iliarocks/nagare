import assert from 'node:assert/strict';
import test from 'node:test';
import { CloudKitError } from '../src/cloudkit.js';
import type { CloudKitRecord, CloudKitValue } from '../src/cloudkit.js';
import { Nagare, NagareError } from '../src/nagare.js';
import type { Mutation, NagareStore, RecordType } from '../src/nagare.js';

const TASK = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';
const THIRD = '33333333-3333-4333-8333-333333333333';
const PROJECT = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA';
const OTHER_PROJECT = 'BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB';
const NOW = Date.parse('2026-10-01T19:00:00Z');
const ZONE = 'America/Los_Angeles';

function record(type: RecordType, recordId: string, values: Record<string, CloudKitValue> = {}): CloudKitRecord {
  const defaults = {
    entityName: type.slice(3), id: recordId, title: type === 'CD_Todo' ? 'Buy apples' : 'Home',
    createdAt: NOW - 86_400_000, modifiedAt: NOW - 86_400_000, syncRecordID: recordId,
    order: 'i', ...(type === 'CD_Todo' ? { scheduledDate: Date.parse('2026-10-01T07:00:00Z'), includesTime: 0 } : {}),
  };
  return {
    recordType: type, recordName: `cloud-${recordId}`, recordChangeTag: 'revision-1',
    fields: Object.fromEntries(Object.entries({ ...defaults, ...values }).map(([key, value]) => [`CD_${key}`, { value }])),
  };
}

class MemoryStore implements NagareStore {
  records: CloudKitRecord[];
  batches: Mutation[][] = [];
  beforeModify?: () => void;

  constructor(...records: CloudKitRecord[]) { this.records = structuredClone(records); }

  async list(type: RecordType) { return structuredClone(this.records.filter(record => record.recordType === type)); }

  async lookup(recordName: string) { return structuredClone(this.records.find(record => record.recordName === recordName)); }

  async modify(operations: Mutation[]) {
    this.beforeModify?.();
    // Validate the entire transaction before changing any record.
    for (const { operationType, record } of operations) {
      const existing = this.records.find(item => item.recordName === record.recordName);
      assert.equal(operationType === 'create', !existing);
      if (existing && record.recordChangeTag !== existing.recordChangeTag) throw new Error('CONFLICT');
    }
    this.batches.push(structuredClone(operations));
    return operations.map(({ record }) => {
      const existing = this.records.find(item => item.recordName === record.recordName);
      const updated = { ...record, fields: { ...existing?.fields, ...record.fields }, recordChangeTag: `revision-${this.batches.length + 1}` };
      this.records = this.records.filter(item => item.recordName !== record.recordName).concat(updated);
      return structuredClone(updated);
    });
  }
}

function setup(...records: CloudKitRecord[]) {
  const store = new MemoryStore(...records);
  return { store, nagare: new Nagare(store, ZONE, () => NOW) };
}

function code(expected: string) {
  return (error: unknown) => error instanceof NagareError && error.code === expected;
}

test('maps logical IDs, project relationships, priority, and local dates from the exported schema', async () => {
  const project = record('CD_Project', PROJECT, { priorityRawValue: 2, isPriority: 0 });
  const todo = record('CD_Todo', TASK, { project: project.recordName, projectOrder: 'i', recurrenceTemplate: 'cloud-template' });
  const { nagare } = setup(project, todo);
  assert.deepEqual(await nagare.listProjects(), [{ id: PROJECT, title: 'Home', notes: null, prioritized: true }]);
  const tasks = await nagare.listTasks({ projectId: PROJECT.toLowerCase(), date: '2026-10-01', completed: false });
  assert.equal(tasks.length, 1);
  assert.equal(tasks[0].projectId, PROJECT);
  assert.equal(tasks[0].date, '2026-10-01');
  assert.equal(tasks[0].time, null);
  assert.equal(tasks[0].recurring, true);
  assert.equal((await nagare.listTasks({ completed: true })).length, 0);
});

test('creates an all-day task at local midnight with native identities and separate global/project ordering', async () => {
  const project = record('CD_Project', PROJECT);
  const active = record('CD_Todo', OTHER, { project: project.recordName, projectOrder: 'i', order: 'z' });
  const done = record('CD_Todo', THIRD, { project: project.recordName, projectOrder: 'z', completedAt: NOW });
  const { nagare, store } = setup(project, active, done);
  const created = await nagare.createTask({ id: TASK, title: 'New task', schedule: { date: '2026-11-02' }, projectId: PROJECT });
  assert.equal(created.scheduledAt, '2026-11-02T08:00:00.000Z');
  const operation = store.batches[0].at(-1)!;
  assert.equal(operation.operationType, 'create');
  const fields = operation.record.fields;
  assert.equal(fields.CD_entityName.value, 'Todo');
  assert.equal(fields.CD_id.value, TASK);
  assert.equal(fields.CD_project.value, project.recordName);
  assert.equal(fields.CD_projectOrder.value, 'r');
  assert.equal(fields.CD_order.value, 'zi');
  assert.equal(fields.CD_modifiedAt.value, NOW);
  assert.equal(fields.CD_createdAt.value, NOW);
  assert.match(fields.CD_syncRecordID.value as string, /^[0-9A-F-]{36}$/);
  assert.notEqual(fields.CD_syncRecordID.value, TASK);
  assert.equal(fields.CD_includesTime.value, 0);
  assert.equal(fields.CD_endDate.value, null);
});

test('replaying a create ID returns the existing task without overwriting intervening edits', async () => {
  const { nagare, store } = setup();
  const input = { id: TASK, title: 'Capture', schedule: { date: '2026-10-01' } };
  await nagare.createTask(input);
  await nagare.updateTask(TASK, { title: 'Edited on Mac' });
  const retry = await nagare.createTask(input);
  assert.equal(retry.title, 'Edited on Mac');
  assert.equal('alreadyExists' in retry && retry.alreadyExists, true);
  assert.equal(store.batches.length, 2);
});

test('text edits send a narrow patch, preserve notes/schedule/identities, and remove only the edited asset companion', async () => {
  const original = record('CD_Todo', TASK, { notes: 'Native notes', calendarIdentifier: 'calendar', title_ckAsset: { fileChecksum: 'old' } });
  const { nagare, store } = setup(original);
  const result = await nagare.updateTask(TASK, { title: 'Edited title' }, 'revision-1');
  assert.deepEqual(Object.keys(store.batches[0][0].record.fields).sort(), ['CD_modifiedAt', 'CD_title', 'CD_title_ckAsset']);
  assert.equal(result.notes, 'Native notes');
  assert.equal(result.title, 'Edited title');
  assert.equal(store.records[0].fields.CD_calendarIdentifier.value, 'calendar');
  assert.equal(store.records[0].fields.CD_syncRecordID.value, TASK);
  assert.equal(store.records[0].fields.CD_title_ckAsset.value, null);
});

test('a stale expected revision and a concurrent CloudKit edit both fail without overwriting data', async () => {
  const { nagare, store } = setup(record('CD_Todo', TASK));
  await assert.rejects(nagare.updateTask(TASK, { title: 'Stale edit' }, 'old-revision'), code('CONFLICT'));
  assert.equal(store.batches.length, 0);
  store.beforeModify = () => {
    store.records[0].recordChangeTag = 'native-revision';
    store.records[0].fields.CD_notes = { value: 'Saved by iPhone' };
  };
  await assert.rejects(nagare.updateTask(TASK, { title: 'Concurrent edit' }), /CONFLICT/);
  assert.equal(store.records[0].fields.CD_title.value, 'Buy apples');
  assert.equal(store.records[0].fields.CD_notes.value, 'Saved by iPhone');
});

test('completion is idempotent and preserves original completion time', async () => {
  const { nagare, store } = setup(record('CD_Todo', TASK));
  const completed = await nagare.completeTask(TASK);
  assert.equal(completed.completedAt, new Date(NOW).toISOString());
  const retry = await nagare.completeTask(TASK);
  assert.equal(retry.completedAt, completed.completedAt);
  assert.equal(store.batches.length, 1);
  assert.deepEqual(Object.keys(store.batches[0][0].record.fields).sort(), ['CD_completedAt', 'CD_modifiedAt']);
});

test('all recurring edits and completions fail closed, including an occurrence with a missing template link', async () => {
  const occurrences: Record<string, CloudKitValue>[] = [{ recurrenceTemplate: 'cloud-template' }, { recurrenceSequence: 0 }];
  for (const recurring of occurrences) {
    const { nagare, store } = setup(record('CD_Todo', TASK, recurring));
    assert.equal((await nagare.listTasks())[0].recurring, true);
    await assert.rejects(nagare.updateTask(TASK, { notes: 'edit' }), code('RECURRING_TASK'));
    await assert.rejects(nagare.completeTask(TASK), code('RECURRING_TASK'));
    assert.equal(store.batches.length, 0);
  }
});

test('an unreadable text asset fails before writing, while explicitly replacing that text clears the asset', async () => {
  for (const fieldName of ['title', 'notes']) {
    const { nagare, store } = setup(record('CD_Todo', TASK, { [fieldName]: '', [`${fieldName}_ckAsset`]: { fileChecksum: 'large' } }));
    await assert.rejects(nagare.updateTask(TASK, { schedule: { date: '2026-10-02' } }), code('EXTERNAL_TEXT'));
    await assert.rejects(nagare.completeTask(TASK), code('EXTERNAL_TEXT'));
    assert.equal(store.batches.length, 0);
    const replaced = await nagare.updateTask(TASK, { [fieldName]: 'Replacement' });
    assert.equal(replaced[fieldName as 'title' | 'notes'], 'Replacement');
    assert.equal(store.records[0].fields[`CD_${fieldName}_ckAsset`].value, null);
  }
});

test('create retries use exact lookup even before CloudKit query indexes include the task', async () => {
  const { nagare, store } = setup();
  const input = { id: TASK, title: 'Capture', schedule: { date: '2026-10-01' } };
  await nagare.createTask(input);
  store.list = async () => [];
  const retry = await nagare.createTask(input);
  assert.equal('alreadyExists' in retry && retry.alreadyExists, true);
  assert.equal(store.batches.length, 1);
});

test('a create collision is recovered through lookup without a second mutation', async () => {
  const { nagare, store } = setup();
  store.modify = async operations => {
    const created = operations.at(-1)!.record;
    store.records.push({ ...created, recordChangeTag: 'created-elsewhere' });
    throw new CloudKitError('ALREADY_EXISTS');
  };
  const result = await nagare.createTask({ id: TASK, title: 'Capture', schedule: { date: '2026-10-01' } });
  assert.equal('alreadyExists' in result && result.alreadyExists, true);
  assert.equal(result.revision, 'created-elsewhere');
  assert.equal(store.records.length, 1);
});

test('moving a timed task retains clock time and duration across a daylight-saving boundary', async () => {
  const task = record('CD_Todo', TASK, {
    scheduledDate: Date.parse('2026-10-31T16:15:00Z'), includesTime: 1,
    endDate: Date.parse('2026-10-31T17:00:00Z'),
  });
  const { nagare } = setup(task);
  const result = await nagare.updateTask(TASK, { schedule: { date: '2026-11-02' } });
  assert.equal(result.scheduledAt, '2026-11-02T17:15:00.000Z');
  assert.equal(result.endAt, '2026-11-02T18:00:00.000Z');
  assert.equal(result.time, '09:15:00');
});

test('a skipped local time moves to the next valid instant, matching Foundation Calendar.nextTime', async () => {
  const task = record('CD_Todo', TASK, {
    scheduledDate: Date.parse('2027-03-13T10:30:00Z'), includesTime: 1,
    endDate: Date.parse('2027-03-13T12:00:00Z'),
  });
  const { nagare } = setup(task);
  const result = await nagare.updateTask(TASK, { schedule: { date: '2027-03-14' } });
  assert.equal(result.scheduledAt, '2027-03-14T10:00:00.000Z');
  assert.equal(result.endAt, '2027-03-14T11:30:00.000Z');
});

test('clearing the start time clears the end and moves to local midnight', async () => {
  const task = record('CD_Todo', TASK, { includesTime: 1, endDate: NOW });
  const { nagare, store } = setup(task);
  const result = await nagare.updateTask(TASK, { schedule: { date: '2026-10-02', time: null } });
  assert.equal(result.scheduledAt, '2026-10-02T07:00:00.000Z');
  assert.equal(result.time, null);
  assert.equal(result.endAt, null);
  assert.equal(store.records[0].fields.CD_includesTime.value, 0);
});

test('rescheduling appends after active items on the destination day, while a same-day time edit retains order', async () => {
  const { nagare, store } = setup(
    record('CD_Todo', TASK, { order: 'a' }),
    record('CD_Todo', OTHER, { order: 'i', scheduledDate: Date.parse('2026-10-02T07:00:00Z') }),
    record('CD_Todo', THIRD, { order: 'z', scheduledDate: Date.parse('2026-10-02T07:00:00Z'), completedAt: NOW }),
  );
  await nagare.updateTask(TASK, { schedule: { date: '2026-10-02' } });
  assert.equal(store.batches[0][0].record.fields.CD_order.value, 'r');
  await nagare.updateTask(TASK, { schedule: { date: '2026-10-02', time: '10:00' } });
  assert.equal(store.batches[1][0].record.fields.CD_order, undefined);
});

test('project changes preserve schedule and append within the new project; detaching clears project order', async () => {
  const project = record('CD_Project', PROJECT);
  const destination = record('CD_Project', OTHER_PROJECT);
  const { nagare, store } = setup(project, destination,
    record('CD_Todo', TASK, { project: project.recordName, projectOrder: 'z' }),
    record('CD_Todo', OTHER, { project: destination.recordName, projectOrder: 'i' }),
  );
  const assigned = await nagare.updateTask(TASK, { projectId: OTHER_PROJECT });
  assert.equal(assigned.projectId, OTHER_PROJECT);
  assert.equal(store.batches[0][0].record.fields.CD_projectOrder.value, 'r');
  assert.equal(store.batches[0][0].record.fields.CD_scheduledDate, undefined);
  await nagare.updateTask(TASK, { projectId: null });
  assert.equal(store.batches[1][0].record.fields.CD_project.value, null);
  assert.equal(store.batches[1][0].record.fields.CD_projectOrder.value, null);
});

test('order repair is atomic and merges global/project repairs for the same item', async () => {
  const project = record('CD_Project', PROJECT);
  const { nagare, store } = setup(project, record('CD_Todo', OTHER, { order: '', project: project.recordName, projectOrder: '' }));
  await nagare.createTask({ id: TASK, title: 'New task', schedule: { date: '2026-10-01' }, projectId: PROJECT });
  assert.equal(store.batches.length, 1);
  assert.equal(store.batches[0].length, 2);
  const repaired = store.batches[0][0].record.fields;
  assert.equal(repaired.CD_order.value, 'hzzzzzzzzzzz');
  assert.equal(repaired.CD_projectOrder.value, 'hzzzzzzzzzzz');
  assert.equal(repaired.CD_modifiedAt.value, NOW);
});

test('unreconciled duplicate logical IDs prevent writes', async () => {
  const task = record('CD_Todo', TASK);
  const { nagare, store } = setup(task, { ...task, recordName: 'duplicate-physical-record' });
  await assert.rejects(nagare.completeTask(TASK), code('SYNC_PENDING'));
  assert.equal(store.batches.length, 0);
});

test('invalid dates, missing projects, blank titles and end-before-start schedules never write', async () => {
  const { nagare, store } = setup(record('CD_Todo', TASK));
  await assert.rejects(nagare.updateTask(TASK, { schedule: { date: '2026-02-30' } }));
  await assert.rejects(nagare.updateTask(TASK, { projectId: PROJECT }), code('NOT_FOUND'));
  await assert.rejects(nagare.updateTask(TASK, { title: '  ' }), code('INVALID_TITLE'));
  await assert.rejects(nagare.updateTask(TASK, { schedule: { date: '2026-10-01', time: '12:00', endTime: '11:00' } }), code('INVALID_SCHEDULE'));
  assert.equal(store.batches.length, 0);
});
