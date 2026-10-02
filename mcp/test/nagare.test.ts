import assert from 'node:assert/strict';
import test from 'node:test';
import { CloudKitError } from '../src/cloudkit.js';
import type { CloudKitRecord, CloudKitValue } from '../src/cloudkit.js';
import { Nagare, NagareError } from '../src/nagare.js';
import type { Mutation, NagareStore, RecordType } from '../src/nagare.js';
import { ruleFields, type Rule } from '../src/recurrence.js';

const TASK = '11111111-1111-4111-8111-111111111111';
const OTHER = '22222222-2222-4222-8222-222222222222';
const THIRD = '33333333-3333-4333-8333-333333333333';
const PROJECT = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA';
const OTHER_PROJECT = 'BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB';
const TEMPLATE = 'CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC';
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

  get(id: string) { return this.records.find(record => record.fields.CD_id.value === id)!; }
  revision(id: string) { return this.get(id).recordChangeTag!; }

  async modify(operations: Mutation[]) {
    this.beforeModify?.();
    // Validate the entire transaction before changing any record.
    for (const { operationType, record } of operations) {
      const existing = this.records.find(item => item.recordName === record.recordName);
      assert.equal(operationType === 'create', !existing);
      if (existing && record.recordChangeTag !== existing.recordChangeTag) throw new Error('CONFLICT');
    }
    this.batches.push(structuredClone(operations));
    return operations.flatMap(({ operationType, record }) => {
      const existing = this.records.find(item => item.recordName === record.recordName);
      if (operationType === 'delete') {
        this.records = this.records.filter(item => item.recordName !== record.recordName);
        return [];
      }
      const updated = { ...record, fields: { ...existing?.fields, ...record.fields }, recordChangeTag: `revision-${this.batches.length + 1}` };
      this.records = this.records.filter(item => item.recordName !== record.recordName).concat(updated);
      return [structuredClone(updated)];
    });
  }
}

function setup(...records: CloudKitRecord[]) {
  return setupAt(NOW, ...records);
}

function setupAt(now: number, ...records: CloudKitRecord[]) {
  const store = new MemoryStore(...records);
  return { store, nagare: new Nagare(store, ZONE, () => now) };
}

function recurringFixture(rule: Rule = { mode: 'relative', unit: 'day', interval: 1 }) {
  const template = record('CD_RecurrenceTemplate', TEMPLATE, {
    title: 'Future title', notes: 'Future notes', currentItemID: TASK, currentSequence: 1,
    startTimeSeconds: 9 * 3600, endTimeSeconds: 10 * 3600,
  });
  Object.assign(template.fields, ruleFields(rule, ZONE));
  const current = record('CD_Todo', TASK, {
    recurrenceTemplate: template.recordName, recurrenceSequence: 1,
    title: 'Current title', notes: 'Current notes', order: 'r', includesTime: 1,
    scheduledDate: Date.parse('2026-10-01T16:00:00Z'), endDate: Date.parse('2026-10-01T17:00:00Z'),
  });
  const history = record('CD_Todo', OTHER, {
    recurrenceTemplate: template.recordName, recurrenceSequence: 0,
    title: 'History title', notes: 'History notes', completedAt: NOW - 86_400_000,
    scheduledDate: Date.parse('2026-09-30T07:00:00Z'),
  });
  return { template, current, history };
}

function code(expected: string) {
  return (error: unknown) => error instanceof NagareError && error.code === expected;
}

test('maps logical IDs, project relationships, priority, and local dates from the exported schema', async () => {
  const project = record('CD_Project', PROJECT, { priorityRawValue: 2, isPriority: 0 });
  const todo = record('CD_Todo', TASK, { project: project.recordName, projectOrder: 'i' });
  const { nagare } = setup(project, todo);
  const projects = await nagare.listProjects();
  assert.equal(projects[0].id, PROJECT);
  assert.equal(projects[0].prioritized, true);
  const tasks = await nagare.listTasks({ projectId: PROJECT.toLowerCase(), date: '2026-10-01' });
  assert.equal(tasks.length, 1);
  assert.equal(tasks[0].projectId, PROJECT);
  assert.equal(tasks[0].date, '2026-10-01');
  assert.equal(tasks[0].time, null);
  assert.equal(tasks[0].recurrence, null);
  assert.equal((await nagare.listCompletedTasks()).length, 0);
});

test('creates an all-day task at local midnight with native identities and separate global/project ordering', async () => {
  const project = record('CD_Project', PROJECT);
  const active = record('CD_Todo', OTHER, { project: project.recordName, projectOrder: 'i', order: 'z' });
  const done = record('CD_Todo', THIRD, { project: project.recordName, projectOrder: 'z', completedAt: NOW });
  const { nagare, store } = setup(project, active, done);
  const created = await nagare.createTask({ id: TASK, title: 'New task', schedule: { date: '2026-11-02' }, projectId: PROJECT });
  assert.equal(created.date, '2026-11-02');
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
  assert.equal(fields.CD_scheduledDate.value, Date.parse('2026-11-02T08:00:00.000Z'));
  assert.equal(fields.CD_endDate.value, null);
});

test('replaying a create ID returns the existing task without overwriting intervening edits', async () => {
  const { nagare, store } = setup();
  const input = { id: TASK, title: 'Capture', schedule: { date: '2026-10-01' } };
  await nagare.createTask(input);
  await nagare.updateTask(TASK, { title: 'Edited on Mac' }, store.revision(TASK));
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
  await assert.rejects(nagare.updateTask(TASK, { title: 'Concurrent edit' }, store.revision(TASK)), /CONFLICT/);
  assert.equal(store.records[0].fields.CD_title.value, 'Buy apples');
  assert.equal(store.records[0].fields.CD_notes.value, 'Saved by iPhone');
});

test('completion is idempotent and preserves original completion time', async () => {
  const { nagare, store } = setup(record('CD_Todo', TASK));
  const completed = await nagare.completeTask(TASK, store.revision(TASK));
  assert.equal(completed.completedOn, '2026-10-01');
  const completedAt = store.get(TASK).fields.CD_completedAt.value;
  const retry = await nagare.completeTask(TASK, completed.revision!);
  assert.equal(retry.completedOn, completed.completedOn);
  assert.equal(store.get(TASK).fields.CD_completedAt.value, completedAt);
  assert.equal(store.batches.length, 1);
  assert.deepEqual(Object.keys(store.batches[0][0].record.fields).sort(), ['CD_completedAt', 'CD_modifiedAt']);
});

test('recurring writes fail closed while their template link is missing', async () => {
  const occurrences: Record<string, CloudKitValue>[] = [{ recurrenceTemplate: 'cloud-template' }, { recurrenceSequence: 0 }];
  for (const recurring of occurrences) {
    const { nagare, store } = setup(record('CD_Todo', TASK, recurring));
    await assert.rejects(nagare.updateTask(TASK, { notes: 'edit' }, store.revision(TASK)), code('SYNC_PENDING'));
    await assert.rejects(nagare.completeTask(TASK, store.revision(TASK)), code('SYNC_PENDING'));
    assert.equal(store.batches.length, 0);
  }
});

test('native zero and negative durations remain readable and roll forward without blocking edits', async () => {
  const yesterday = Date.parse('2026-09-30T16:00:00Z');
  const today = Date.parse('2026-10-01T16:00:00Z');
  for (const duration of [0, -3_600_000]) {
    const { nagare, store } = setup(record('CD_Todo', TASK, {
      includesTime: 1, scheduledDate: yesterday, endDate: yesterday + duration,
    }));
    assert.equal((await nagare.listTasks({ date: 'today' }))[0].date, '2026-10-01');
    assert.equal(store.batches.length, 0);
    await nagare.updateTask(TASK, { title: 'Keep the native duration' }, store.revision(TASK));
    assert.equal(store.get(TASK).fields.CD_scheduledDate.value, today);
    assert.equal(store.get(TASK).fields.CD_endDate.value, today + duration);
    await assert.rejects(nagare.updateTask(TASK, {
      schedule: { date: '2026-10-02', time: '09:00', endTime: '08:00' },
    }, store.revision(TASK)), code('INVALID_SCHEDULE'));
    assert.equal(store.batches.length, 1);
  }
});

test('explicit repeat removal clears an orphan without changing its task or unrelated series', async () => {
  for (const link of [null, 'deleted-template']) {
    const { template, current } = recurringFixture();
    const orphan = record('CD_Todo', THIRD, { recurrenceTemplate: link, recurrenceSequence: 2, notes: 'Keep these notes' });
    const { nagare, store } = setup(orphan, template, current);
    await assert.rejects(nagare.updateTask(THIRD, { recurrence: null }, 'stale-revision'), code('CONFLICT'));
    const result = await nagare.updateTask(THIRD, { recurrence: null }, store.revision(THIRD));
    assert.equal(result.recurrence, null);
    assert.equal(result.title, 'Buy apples');
    assert.equal(result.notes, 'Keep these notes');
    assert.equal(store.get(THIRD).fields.CD_recurrenceSequence.value, null);
    assert.equal(store.get(THIRD).fields.CD_recurrenceTemplate.value, null);
    assert.equal(store.get(TEMPLATE).recordChangeTag, 'revision-1');
    assert.equal(store.batches[0].length, 1);
  }
});

test('explicit repeat removal resolves an unambiguous missing inverse link and rejects competing templates', async () => {
  const { template, current, history } = recurringFixture();
  current.fields.CD_recurrenceTemplate.value = null;
  const { nagare, store } = setup(template, current, history);
  await nagare.updateTask(TASK, { recurrence: null }, store.revision(TASK));
  assert.equal(store.records.some(item => item.recordName === template.recordName), false);
  for (const taskId of [TASK, OTHER]) assert.equal(store.get(taskId).fields.CD_recurrenceSequence.value, null);

  const competing = structuredClone(template);
  competing.recordName += '-competing';
  competing.fields.CD_id.value = PROJECT;
  const ambiguous = setup(template, competing, current);
  await assert.rejects(ambiguous.nagare.updateTask(TASK, { recurrence: null }, 'revision-1'), code('SYNC_PENDING'));
  assert.equal(ambiguous.store.batches.length, 0);
});

test('an unreadable text asset fails before writing, while explicitly replacing that text clears the asset', async () => {
  for (const fieldName of ['title', 'notes']) {
    const { nagare, store } = setup(record('CD_Todo', TASK, { [fieldName]: '', [`${fieldName}_ckAsset`]: { fileChecksum: 'large' } }));
    await assert.rejects(nagare.updateTask(TASK, { schedule: { date: '2026-10-02' } }, store.revision(TASK)), code('EXTERNAL_TEXT'));
    await assert.rejects(nagare.completeTask(TASK, store.revision(TASK)), code('EXTERNAL_TEXT'));
    assert.equal(store.batches.length, 0);
    const replaced = await nagare.updateTask(TASK, { [fieldName]: 'Replacement' }, store.revision(TASK));
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
    throw new CloudKitError('ALREADY_EXISTS', 200, [{ serverErrorCode: 'ALREADY_EXISTS', recordName: created.recordName }]);
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
  const { nagare, store } = setup(task);
  const result = await nagare.updateTask(TASK, { schedule: { date: '2026-11-02' } }, store.revision(TASK));
  assert.equal(store.get(TASK).fields.CD_scheduledDate.value, Date.parse('2026-11-02T17:15:00.000Z'));
  assert.equal(store.get(TASK).fields.CD_endDate.value, Date.parse('2026-11-02T18:00:00.000Z'));
  assert.equal(result.time, '09:15');
});

test('a skipped local time moves to the next valid instant, matching Foundation Calendar.nextTime', async () => {
  const task = record('CD_Todo', TASK, {
    scheduledDate: Date.parse('2027-03-13T10:30:00Z'), includesTime: 1,
    endDate: Date.parse('2027-03-13T12:00:00Z'),
  });
  const { nagare, store } = setup(task);
  await nagare.updateTask(TASK, { schedule: { date: '2027-03-14' } }, store.revision(TASK));
  assert.equal(store.get(TASK).fields.CD_scheduledDate.value, Date.parse('2027-03-14T10:00:00.000Z'));
  assert.equal(store.get(TASK).fields.CD_endDate.value, Date.parse('2027-03-14T11:30:00.000Z'));
});

test('clearing the start time clears the end and moves to local midnight', async () => {
  const task = record('CD_Todo', TASK, { includesTime: 1, endDate: NOW });
  const { nagare, store } = setup(task);
  const result = await nagare.updateTask(TASK, { schedule: { date: '2026-10-02', time: null } }, store.revision(TASK));
  assert.equal(store.get(TASK).fields.CD_scheduledDate.value, Date.parse('2026-10-02T07:00:00.000Z'));
  assert.equal(result.time, null);
  assert.equal(result.endTime, null);
  assert.equal(store.records[0].fields.CD_includesTime.value, 0);
});

test('rescheduling appends after active items on the destination day, while a same-day time edit retains order', async () => {
  const { nagare, store } = setup(
    record('CD_Todo', TASK, { order: 'a' }),
    record('CD_Todo', OTHER, { order: 'i', scheduledDate: Date.parse('2026-10-02T07:00:00Z') }),
    record('CD_Todo', THIRD, { order: 'z', scheduledDate: Date.parse('2026-10-02T07:00:00Z'), completedAt: NOW }),
  );
  await nagare.updateTask(TASK, { schedule: { date: '2026-10-02' } }, store.revision(TASK));
  assert.equal(store.batches[0][0].record.fields.CD_order.value, 'r');
  await nagare.updateTask(TASK, { schedule: { date: '2026-10-02', time: '10:00' } }, store.revision(TASK));
  assert.equal(store.batches[1][0].record.fields.CD_order, undefined);
});

test('project changes preserve schedule and append within the new project; detaching clears project order', async () => {
  const project = record('CD_Project', PROJECT);
  const destination = record('CD_Project', OTHER_PROJECT);
  const { nagare, store } = setup(project, destination,
    record('CD_Todo', TASK, { project: project.recordName, projectOrder: 'z' }),
    record('CD_Todo', OTHER, { project: destination.recordName, projectOrder: 'i' }),
  );
  const assigned = await nagare.updateTask(TASK, { projectId: OTHER_PROJECT }, store.revision(TASK));
  assert.equal(assigned.projectId, OTHER_PROJECT);
  assert.equal(store.batches[0][0].record.fields.CD_projectOrder.value, 'r');
  assert.equal(store.batches[0][0].record.fields.CD_scheduledDate, undefined);
  await nagare.updateTask(TASK, { projectId: null }, store.revision(TASK));
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
  await assert.rejects(nagare.completeTask(TASK, store.revision(TASK)), code('SYNC_PENDING'));
  assert.equal(store.batches.length, 0);
});

test('invalid dates, missing projects, blank titles and end-before-start schedules never write', async () => {
  const { nagare, store } = setup(record('CD_Todo', TASK));
  await assert.rejects(nagare.updateTask(TASK, { schedule: { date: '2026-02-30' } }, store.revision(TASK)));
  await assert.rejects(nagare.updateTask(TASK, { projectId: PROJECT }, store.revision(TASK)), code('NOT_FOUND'));
  await assert.rejects(nagare.updateTask(TASK, { title: '  ' }, store.revision(TASK)), code('INVALID_TITLE'));
  await assert.rejects(nagare.updateTask(TASK, { schedule: { date: '2026-10-01', time: '12:00', endTime: '11:00' } }, store.revision(TASK)), code('INVALID_SCHEDULE'));
  assert.equal(store.batches.length, 0);
});

test('active tasks and completed history are separate; history filters use completion dates and never project recurrence', async () => {
  const { template, current, history } = recurringFixture();
  const otherDone = record('CD_Todo', THIRD, {
    title: 'Second completed', completedAt: NOW, scheduledDate: Date.parse('2026-09-20T07:00:00Z'),
  });
  const { nagare, store } = setup(template, current, history, otherDone);
  const active = await nagare.listTasks({ from: '2026-10-01', through: '2026-10-03' });
  assert.equal(active.filter(task => !task.virtual).length, 1);
  assert.equal(active[0].id, TASK);
  assert.ok(active.every(task => task.completedOn === undefined));
  const completed = await nagare.listCompletedTasks();
  assert.deepEqual(completed.map(task => task.id), [THIRD, OTHER]);
  assert.ok(completed.every(task => !task.virtual));
  assert.equal(completed[0].date, '2026-09-20');
  assert.equal(completed[0].completedOn, '2026-10-01');
  assert.deepEqual((await nagare.listCompletedTasks({ from: '2026-10-01', through: '2026-10-01' })).map(task => task.id), [THIRD]);
  assert.deepEqual((await nagare.listCompletedTasks({ query: 'HISTORY NOTES' })).map(task => task.id), [OTHER]);
  assert.equal(store.batches.length, 0);
});

test('closed-app rollover reads today and October 3 projections without mutating persisted data', async () => {
  const { template, current, history } = recurringFixture();
  const tomorrow = Date.parse('2026-10-02T19:00:00Z');
  const { nagare, store } = setupAt(tomorrow, template, current, history);
  const before = structuredClone(store.records);
  const today = await nagare.listTasks({ date: 'today' });
  assert.equal(today.length, 1);
  assert.equal(today[0].date, '2026-10-02');
  assert.equal(today[0].time, '09:00');
  assert.equal(today[0].endTime, '10:00');
  assert.equal(today[0].virtual, false);
  const projected = await nagare.listTasks({ date: '2026-10-03' });
  assert.equal(projected.length, 1);
  assert.equal(projected[0].virtual, true);
  assert.equal(projected[0].date, '2026-10-03');
  assert.equal(projected[0].title, 'Future title');
  assert.equal(projected[0].notes, 'Future notes');
  assert.equal(projected[0].revision, undefined);
  assert.equal(projected[0].recurrence?.id, TEMPLATE);
  assert.equal((await nagare.listTasks({ date: 'tomorrow' }))[0].id, projected[0].id);
  assert.equal(store.batches.length, 0);
  assert.deepEqual(store.records, before);
  const completed = await nagare.listCompletedTasks();
  assert.equal(completed[0].date, '2026-09-30');
});

test('an authorized write commits pending rollover and its own patch in one atomic batch', async () => {
  const { nagare, store } = setupAt(Date.parse('2026-10-02T19:00:00Z'),
    record('CD_Todo', TASK, { title: 'Overdue', order: 'a' }),
    record('CD_Todo', OTHER, { title: 'Today', order: 'i', scheduledDate: Date.parse('2026-10-02T07:00:00Z') }),
  );
  const edited = await nagare.updateTask(TASK, { notes: 'Written remotely' }, store.revision(TASK));
  assert.equal(edited.date, '2026-10-02');
  assert.equal(edited.notes, 'Written remotely');
  assert.equal(store.batches.length, 1);
  assert.equal(store.batches[0].length, 1);
  assert.equal(store.get(TASK).fields.CD_scheduledDate.value, Date.parse('2026-10-02T07:00:00Z'));
  assert.deepEqual((await nagare.listTasks({ date: 'today' })).map(task => task.id), [OTHER, TASK]);
});

test('recurring creation atomically creates the native template and first occurrence and remains idempotent', async () => {
  const { nagare, store } = setup();
  const input = {
    id: TASK, title: 'Daily review', notes: 'Review notes', schedule: { date: '2026-10-01', time: '09:15', endTime: '10:00' },
    recurrence: { mode: 'relative', unit: 'day', interval: 2 } as const,
  };
  const created = await nagare.createTask(input);
  assert.ok(created.recurrence);
  assert.equal(store.batches.length, 1);
  assert.equal(store.batches[0].length, 2);
  const series = await nagare.listRecurrences();
  assert.equal(series.length, 1);
  assert.equal(series[0].currentTaskId, TASK);
  assert.equal(series[0].time, '09:15');
  assert.equal(series[0].endTime, '10:00');
  assert.equal((await nagare.listTasks({ date: '2026-10-03' }))[0].virtual, true);
  const retry = await nagare.createTask(input);
  assert.equal(retry.alreadyExists, true);
  assert.equal(retry.recurrence?.id, created.recurrence.id);
  assert.equal(store.batches.length, 1);
});

test('current occurrence edits and future template edits preserve each other’s content and times', async () => {
  const { template, current, history } = recurringFixture();
  const { nagare, store } = setup(template, current, history);
  await nagare.updateTask(TASK, { title: 'Only this time', notes: 'Current edited', schedule: { date: '2026-10-01', time: '10:30', endTime: '11:00' } }, store.revision(TASK));
  assert.equal((await nagare.listRecurrences())[0].title, 'Future title');
  let future = (await nagare.listTasks({ date: '2026-10-02' }))[0];
  assert.equal(future.title, 'Future title');
  assert.equal(future.time, '09:00');
  await nagare.updateRecurrence(TEMPLATE, { title: 'Future edited', notes: 'Future revised', time: '11:30', endTime: '12:30' }, store.revision(TEMPLATE));
  const today = (await nagare.listTasks({ date: 'today' }))[0];
  assert.equal(today.title, 'Only this time');
  assert.equal(today.notes, 'Current edited');
  assert.equal(today.time, '10:30');
  future = (await nagare.listTasks({ date: 'tomorrow' }))[0];
  assert.equal(future.title, 'Future edited');
  assert.equal(future.notes, 'Future revised');
  assert.equal(future.time, '11:30');
  assert.equal(future.endTime, '12:30');
  assert.equal(store.get(OTHER).fields.CD_title.value, 'History title');
});

test('completing a recurrence preserves history and creates exactly one successor from future content', async () => {
  const { template, current, history } = recurringFixture();
  const { nagare, store } = setup(template, current, history);
  const completed = await nagare.completeTask(TASK, store.revision(TASK));
  assert.equal(completed.completedOn, '2026-10-01');
  assert.equal(completed.title, 'Current title');
  assert.equal(store.batches.length, 1);
  assert.equal(store.batches[0].length, 3);
  const next = (await nagare.listTasks({ date: '2026-10-02' }))[0];
  assert.equal(next.virtual, false);
  assert.equal(next.title, 'Future title');
  assert.equal(next.notes, 'Future notes');
  assert.notEqual(next.id, TASK);
  assert.equal(next.recurrence?.id, TEMPLATE);
  assert.equal(store.get(next.id).fields.CD_order.value, current.fields.CD_order.value);
  assert.equal(store.get(TEMPLATE).fields.CD_currentItemID.value, next.id);
  assert.equal(store.get(TEMPLATE).fields.CD_currentSequence.value, 2);
  await nagare.completeTask(TASK, completed.revision!);
  assert.equal(store.batches.length, 1);
  assert.equal((await nagare.listCompletedTasks()).length, 2);
});

test('deleting a current recurrence advances once; deleting completed history does not advance again', async () => {
  const { template, current, history } = recurringFixture();
  const { nagare, store } = setup(template, current, history);
  await nagare.deleteTask(TASK, store.revision(TASK));
  assert.equal(store.get(TASK), undefined);
  const next = (await nagare.listTasks({ date: 'tomorrow' }))[0];
  assert.equal(next.virtual, false);
  assert.equal(store.batches[0].filter(operation => operation.operationType === 'delete').length, 1);
  assert.equal(store.get(TEMPLATE).fields.CD_currentSequence.value, 2);
  await nagare.deleteTask(OTHER, store.revision(OTHER));
  assert.equal(store.get(OTHER), undefined);
  assert.equal(store.batches[1].length, 1);
  assert.equal(store.get(TEMPLATE).fields.CD_currentSequence.value, 2);
  assert.equal((await nagare.listTasks({ date: 'tomorrow' }))[0].id, next.id);
});

test('stopping a recurrence deletes its template while preserving and detaching current and completed tasks', async () => {
  const { template, current, history } = recurringFixture();
  const { nagare, store } = setup(template, current, history);
  const stopped = await nagare.stopRecurrence(TEMPLATE, store.revision(TEMPLATE));
  assert.equal(stopped.id, TASK);
  assert.equal(stopped.recurrence, null);
  assert.equal(stopped.title, 'Current title');
  assert.equal(store.get(TEMPLATE), undefined);
  assert.equal(store.get(OTHER).fields.CD_completedAt.value, history.fields.CD_completedAt.value);
  for (const taskId of [TASK, OTHER]) {
    assert.equal(store.get(taskId).fields.CD_recurrenceTemplate.value, null);
    assert.equal(store.get(taskId).fields.CD_recurrenceSequence.value, null);
  }
  assert.equal((await nagare.listRecurrences()).length, 0);
  assert.equal((await nagare.listTasks({ date: 'tomorrow' })).length, 0);
  assert.equal(store.batches.length, 1);
});

test('reinstating completed recurrence history creates an ordinary task without disturbing the running series', async () => {
  const { template, current, history } = recurringFixture();
  const { nagare, store } = setup(template, current, history);
  const reinstated = await nagare.reinstateTask(OTHER, store.revision(OTHER));
  assert.equal(reinstated.id, OTHER);
  assert.equal(reinstated.date, '2026-10-01');
  assert.equal(reinstated.completedOn, undefined);
  assert.equal(reinstated.recurrence, null);
  assert.equal(reinstated.title, 'History title');
  assert.equal(store.get(TEMPLATE).fields.CD_currentItemID.value, TASK);
  assert.equal(store.get(TEMPLATE).fields.CD_currentSequence.value, 1);
  assert.deepEqual((await nagare.listTasks({ date: 'today' })).map(task => task.id), [TASK, OTHER]);
  assert.equal((await nagare.listCompletedTasks()).length, 0);
});

test('reordering a block between date lists preserves supplied order, task time, duration and project membership', async () => {
  const project = record('CD_Project', PROJECT);
  const { nagare, store } = setup(project,
    record('CD_Todo', TASK, { project: project.recordName, projectOrder: 'i', order: 'a', includesTime: 1,
      scheduledDate: Date.parse('2026-10-01T16:00:00Z'), endDate: Date.parse('2026-10-01T17:00:00Z') }),
    record('CD_Todo', OTHER, { order: 'i', scheduledDate: Date.parse('2026-10-02T07:00:00Z') }),
    record('CD_Todo', THIRD, { order: 'z' }),
  );
  await nagare.reorderTasks({ ids: [THIRD, TASK], revisions: { [TASK]: store.revision(TASK), [THIRD]: store.revision(THIRD) }, date: '2026-10-02', beforeId: OTHER });
  const tasks = await nagare.listTasks({ date: '2026-10-02' });
  assert.deepEqual(tasks.map(task => task.id), [THIRD, TASK, OTHER]);
  assert.equal(tasks[1].time, '09:00');
  assert.equal(tasks[1].endTime, '10:00');
  assert.equal(tasks[1].projectId, PROJECT);
  assert.equal(store.get(TASK).fields.CD_projectOrder.value, 'i');
  assert.equal(store.batches.length, 1);
});

test('project reordering updates a recurring task and its future project while preserving its calendar position', async () => {
  const { template, current } = recurringFixture();
  const destination = record('CD_Project', PROJECT);
  const { nagare, store } = setup(template, current, destination,
    record('CD_Todo', OTHER, { project: destination.recordName, projectOrder: 'i' }),
  );
  await nagare.reorderTasks({ ids: [TASK], revisions: { [TASK]: store.revision(TASK) }, projectId: PROJECT, beforeId: OTHER });
  const tasks = await nagare.listTasks({ projectId: PROJECT });
  assert.deepEqual(tasks.map(task => task.id), [TASK, OTHER]);
  assert.equal(store.get(TEMPLATE).fields.CD_project.value, destination.recordName);
  assert.equal(store.get(TASK).fields.CD_scheduledDate.value, current.fields.CD_scheduledDate.value);
  assert.equal(store.get(TASK).fields.CD_order.value, current.fields.CD_order.value);
  assert.equal((await nagare.listTasks({ date: 'tomorrow' }))[0].projectId, PROJECT);
});

test('an atomic recurrence completion conflict leaves no successor and preserves both current task and template', async () => {
  const { template, current } = recurringFixture();
  const { nagare, store } = setup(template, current);
  store.beforeModify = () => { store.get(TEMPLATE).recordChangeTag = 'edited-on-phone'; };
  await assert.rejects(nagare.completeTask(TASK, store.revision(TASK)), /CONFLICT/);
  assert.equal(store.batches.length, 0);
  assert.equal(store.records.filter(record => record.recordType === 'CD_Todo').length, 1);
  assert.equal(store.get(TASK).fields.CD_completedAt, undefined);
  assert.equal(store.get(TEMPLATE).fields.CD_currentItemID.value, TASK);
  assert.equal(store.get(TEMPLATE).fields.CD_currentSequence.value, 1);
});

test('a partially synced recurrence without its current occurrence does not block unrelated reads', async () => {
  const { template, history } = recurringFixture();
  const { nagare, store } = setup(template, history, record('CD_Todo', THIRD, { title: 'Independent task' }));
  assert.deepEqual((await nagare.listTasks()).map(task => task.id), [THIRD]);
  assert.deepEqual(await nagare.listTasks({ date: 'tomorrow' }), []);
  assert.equal((await nagare.listCompletedTasks())[0].id, OTHER);
  assert.equal((await nagare.listRecurrences())[0].id, TEMPLATE);
  assert.equal(store.batches.length, 0);
});

test('an invalid stored repeat rule leaves tasks readable and editable, and retains metadata for repair', async () => {
  const { template, current } = recurringFixture();
  template.fields.CD_interval = { value: 0 };
  const { nagare, store } = setupAt(NOW + 86_400_000, template, current, record('CD_Todo', THIRD));
  const tasks = await nagare.listTasks();
  assert.deepEqual(new Set(tasks.map(task => task.id)), new Set([TASK, THIRD]));
  const recurrence = tasks.find(task => task.id === TASK)!.recurrence!;
  assert.equal(recurrence.id, TEMPLATE);
  assert.equal(recurrence.revision, 'revision-1');
  assert.equal(recurrence.rule, null);
  assert.match(recurrence.error!, /update_recurrence/);
  assert.equal((await nagare.listRecurrences())[0].rule, null);
  assert.equal(store.batches.length, 0);

  await assert.rejects(nagare.completeTask(TASK, store.revision(TASK)), code('INVALID_RECURRENCE'));
  assert.equal(store.batches.length, 0);
  await nagare.updateTask(THIRD, { title: 'Independent edit' }, store.revision(THIRD));
  await nagare.updateTask(TASK, { notes: 'Keep the current occurrence usable' }, store.revision(TASK));
  assert.equal(store.get(THIRD).fields.CD_title.value, 'Independent edit');
  const repaired = await nagare.updateRecurrence(TEMPLATE, {
    rule: { mode: 'relative', unit: 'day', interval: 1 },
  }, store.revision(TEMPLATE));
  assert.equal(repaired.rule!.interval, 1);
  assert.equal((await nagare.listTasks({ date: 'tomorrow' }))[0].virtual, true);
});

function overdueTasks(count: number) {
  return Array.from({ length: count }, (_, index) => record('CD_Todo',
    String(index).padStart(8, '0') + '-0000-4000-8000-000000000000', {
      scheduledDate: Date.parse('2026-09-30T07:00:00Z'), order: index.toString(36).padStart(4, '0'),
    }));
}

test('large rollover preserves order and rebases one atomic edit onto acknowledged maintenance revisions', async () => {
  const tasks = overdueTasks(405);
  const target = tasks[202].fields.CD_id.value as string;
  const { nagare, store } = setup(...tasks);
  const before = (await nagare.listTasks({ date: 'today' })).map(task => task.id);
  assert.equal(store.batches.length, 0);
  const changed = await nagare.updateTask(target, { title: 'Edited middle task' }, store.revision(target));
  assert.equal(changed.title, 'Edited middle task');
  assert.deepEqual(store.batches.map(batch => batch.length), [200, 200, 5, 1]);
  assert.equal(store.batches[3][0].record.recordChangeTag, 'revision-3');
  assert.deepEqual(Object.keys(store.batches[3][0].record.fields).sort(), ['CD_modifiedAt', 'CD_title', 'CD_title_ckAsset']);
  assert.deepEqual((await nagare.listTasks({ date: 'today' })).map(task => task.id), before);
});

test('interrupted large rollover leaves an ordered prefix and does not apply the requested edit', async () => {
  const tasks = overdueTasks(205);
  const target = tasks[100].fields.CD_id.value as string;
  const { nagare, store } = setup(...tasks);
  const before = (await nagare.listTasks({ date: 'today' })).map(task => task.id);
  store.beforeModify = () => {
    if (store.batches.length === 1) throw new Error('Connection interrupted');
  };
  await assert.rejects(nagare.updateTask(target, { title: 'Must stay unapplied' }, store.revision(target)), /Connection interrupted/);
  assert.deepEqual(store.batches.map(batch => batch.length), [200]);
  assert.equal(store.get(target).fields.CD_title.value, 'Buy apples');
  assert.equal(store.records.filter(task => task.fields.CD_scheduledDate.value === Date.parse('2026-09-30T07:00:00Z')).length, 5);
  assert.deepEqual((await nagare.listTasks({ date: 'today' })).map(task => task.id), before);
});

test('an oversized requested command is rejected before persisting any day maintenance', async () => {
  const tasks = overdueTasks(205);
  const { nagare, store } = setup(...tasks);
  const ids = tasks.map(task => task.fields.CD_id.value as string);
  await assert.rejects(nagare.reorderTasks({
    ids, revisions: Object.fromEntries(ids.map(taskId => [taskId, store.revision(taskId)])), date: '2026-10-02',
  }), code('TRANSACTION_TOO_LARGE'));
  assert.equal(store.batches.length, 0);
});

test('a native edit after large maintenance still conflicts with the requested command', async () => {
  const tasks = overdueTasks(205);
  const target = tasks[100].fields.CD_id.value as string;
  const { nagare, store } = setup(...tasks);
  store.beforeModify = () => {
    if (store.batches.length === 2) {
      store.get(target).recordChangeTag = 'edited-on-phone';
      store.get(target).fields.CD_title = { value: 'Phone edit' };
    }
  };
  await assert.rejects(nagare.updateTask(target, { title: 'Concurrent edit' }, store.revision(target)), /CONFLICT/);
  assert.deepEqual(store.batches.map(batch => batch.length), [200, 5]);
  assert.equal(store.get(target).fields.CD_title.value, 'Phone edit');
});

test('virtual recurrence times normalize a spring-forward gap just like the realized successor', async () => {
  const { template, current } = recurringFixture();
  template.fields.CD_startTimeSeconds = { value: 2 * 3600 + 30 * 60 };
  template.fields.CD_endTimeSeconds = { value: 4 * 3600 };
  current.fields.CD_scheduledDate = { value: Date.parse('2027-03-13T10:30:00Z') };
  current.fields.CD_endDate = { value: Date.parse('2027-03-13T12:00:00Z') };
  const { nagare, store } = setupAt(Date.parse('2027-03-13T20:00:00Z'), template, current);
  const projected = (await nagare.listTasks({ date: '2027-03-14' }))[0];
  assert.equal(projected.virtual, true);
  assert.equal(projected.time, '03:00');
  assert.equal(projected.endTime, '04:00');
  assert.equal(store.batches.length, 0);
  await nagare.completeTask(TASK, store.revision(TASK));
  const realized = (await nagare.listTasks({ date: '2027-03-14' }))[0];
  assert.equal(realized.virtual, false);
  assert.equal(realized.time, projected.time);
  assert.equal(realized.endTime, projected.endTime);
});

test('changing a completed occurrence’s project leaves its running template and current occurrence in their project', async () => {
  const { template, current, history } = recurringFixture();
  const originalProject = record('CD_Project', PROJECT);
  const destination = record('CD_Project', OTHER_PROJECT);
  for (const item of [template, current, history]) item.fields.CD_project = { value: originalProject.recordName };
  const { nagare, store } = setup(template, current, history, originalProject, destination);
  const changed = await nagare.updateTask(OTHER, { projectId: OTHER_PROJECT }, store.revision(OTHER));
  assert.equal(changed.projectId, OTHER_PROJECT);
  assert.equal(store.get(TEMPLATE).fields.CD_project.value, originalProject.recordName);
  assert.equal(store.get(TASK).fields.CD_project.value, originalProject.recordName);
  assert.equal((await nagare.listTasks({ date: 'tomorrow' }))[0].projectId, PROJECT);
  assert.equal((await nagare.listCompletedTasks({ projectId: OTHER_PROJECT }))[0].id, OTHER);
});

test('project context lists saved tasks in project order while dated project queries include calendar projections', async () => {
  const { template, current } = recurringFixture();
  const project = record('CD_Project', PROJECT);
  template.fields.CD_project = { value: project.recordName };
  current.fields.CD_project = { value: project.recordName };
  current.fields.CD_projectOrder = { value: 'i' };
  const { nagare, store } = setup(project, template, current,
    record('CD_Todo', OTHER, { project: project.recordName, projectOrder: 'a', scheduledDate: Date.parse('2026-10-04T07:00:00Z') }),
  );
  const projectTasks = await nagare.listTasks({ projectId: PROJECT });
  assert.deepEqual(projectTasks.map(task => task.id), [OTHER, TASK]);
  assert.ok(projectTasks.every(task => !task.virtual));
  const tomorrow = await nagare.listTasks({ projectId: PROJECT, date: 'tomorrow' });
  assert.equal(tomorrow.length, 1);
  assert.equal(tomorrow[0].virtual, true);
  const calendarTasks = await nagare.listTasks({ projectId: PROJECT, from: '2026-10-01', through: '2026-10-04' });
  assert.deepEqual(calendarTasks.map(task => task.date), ['2026-10-01', '2026-10-02', '2026-10-04']);
  assert.deepEqual(calendarTasks.map(task => task.virtual), [false, true, false]);
  assert.equal(store.batches.length, 0);
});

test('recurrence project filters distinguish all series, a selected project, and unassigned series', async () => {
  const { template, current } = recurringFixture();
  const project = record('CD_Project', PROJECT);
  template.fields.CD_project = { value: project.recordName };
  current.fields.CD_project = { value: project.recordName };
  const unassigned = record('CD_RecurrenceTemplate', THIRD, {
    title: 'Unassigned series', currentItemID: OTHER, currentSequence: 0, startTimeSeconds: null, endTimeSeconds: null,
  });
  Object.assign(unassigned.fields, ruleFields({ mode: 'relative', unit: 'week', interval: 1 }, ZONE));
  const { nagare, store } = setup(project, template, current, unassigned,
    record('CD_Todo', OTHER, { recurrenceTemplate: unassigned.recordName, recurrenceSequence: 0 }),
  );
  assert.equal((await nagare.listRecurrences()).length, 2);
  assert.deepEqual((await nagare.listRecurrences({ projectId: PROJECT.toLowerCase() })).map(series => series.id), [TEMPLATE]);
  assert.deepEqual((await nagare.listRecurrences({ projectId: null })).map(series => series.id), [THIRD]);
  assert.deepEqual((await nagare.listTasks({ projectId: null })).map(task => task.id), [OTHER]);
  await assert.rejects(nagare.listRecurrences({ projectId: OTHER_PROJECT }), code('NOT_FOUND'));
  assert.equal(store.batches.length, 0);
});
