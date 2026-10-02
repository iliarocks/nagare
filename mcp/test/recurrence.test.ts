import assert from 'node:assert/strict';
import test from 'node:test';
import { Buffer } from 'node:buffer';
import createPlist from 'bplist-creator';
import type { CloudKitRecord, CloudKitValue } from '../src/cloudkit.js';
import { NagareError, value } from '../src/records.js';
import { advancePlan, createTemplatePlan, decodeAnchors, editTemplatePlan, encodeAnchors, nextDate, normalizeRule, occurrenceSchedule, ruleFields, ruleFromRecord, stopPlan, virtualDates } from '../src/recurrence.js';
import type { Rule } from '../src/recurrence.js';

const TASK = '11111111-1111-4111-8111-111111111111';
const HISTORY = '22222222-2222-4222-8222-222222222222';
const TEMPLATE = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA';
const NOW = Date.parse('2026-07-01T18:00:00Z');
const ZONE = 'America/Los_Angeles';
const relative = (unit: Rule['unit'] = 'day', interval = 1): Rule => ({ mode: 'relative', unit, interval });
const absolute = (unit: Rule['unit'], interval: number, reference: string, anchors?: number[]): Rule => ({ mode: 'absolute', unit, interval, reference, anchors });
const invalid = (error: unknown) => error instanceof NagareError && error.code === 'INVALID_RECURRENCE';

function record(recordType: string, recordId: string, fields: Record<string, CloudKitValue>): CloudKitRecord {
  return {
    recordType, recordName: `${recordType}_${recordId}`, recordChangeTag: 'revision-1',
    fields: Object.fromEntries(Object.entries({ id: recordId, ...fields }).map(([key, value]) => [`CD_${key}`, { value }])),
  };
}

function fixture(rule: Rule = relative(), taskFields: Record<string, CloudKitValue> = {}) {
  const todo = record('CD_Todo', TASK, {
    title: 'Current title', notes: 'Current notes', order: 'r', projectOrder: 'c', project: 'cloud-project',
    scheduledDate: Date.parse('2026-07-01T07:00:00Z'), includesTime: 0,
    recurrenceTemplate: `CD_RecurrenceTemplate_${TEMPLATE}`, recurrenceSequence: 1, ...taskFields,
  });
  const template = record('CD_RecurrenceTemplate', TEMPLATE, {
    title: 'Future title', notes: 'Future notes', project: 'cloud-project', currentItemID: TASK, currentSequence: 1,
    startTimeSeconds: null, endTimeSeconds: null,
  });
  Object.assign(template.fields, ruleFields(rule, ZONE));
  const history = record('CD_Todo', HISTORY, {
    title: 'Previous', scheduledDate: Date.parse('2026-06-30T07:00:00Z'), completedAt: NOW - 86_400_000,
    recurrenceTemplate: template.recordName, recurrenceSequence: 0, order: 'r',
  });
  return { todo, template, history };
}

test('relative date arithmetic matches native day/week/month/year and leap-day fixtures', () => {
  const cases: [Rule, string, string][] = [
    [relative('day'), '2026-07-23', '2026-07-24'],
    [relative('week', 2), '2026-07-23', '2026-08-06'],
    [relative('month'), '2024-01-31', '2024-02-29'],
    [relative('month'), '2025-01-31', '2025-02-28'],
    [relative('year'), '2026-08-03', '2027-08-03'],
    [relative('year'), '2024-02-29', '2025-02-28'],
  ];
  for (const [rule, current, expected] of cases) assert.equal(nextDate(current, rule), expected);
});

test('absolute dates preserve reference phase and use Monday-based weekly anchors', () => {
  const cases: [Rule, string, string][] = [
    [absolute('day', 3, '2026-01-01'), '2026-01-02', '2026-01-04'],
    [absolute('day', 3, '2026-01-01'), '2026-01-04', '2026-01-07'],
    [absolute('day', 3, '2026-01-10'), '2026-01-02', '2026-01-10'],
    [absolute('week', 1, '2026-01-07', [6, 0, 3]), '2026-01-05', '2026-01-08'],
    [absolute('week', 1, '2026-01-07', [6, 0, 3]), '2026-01-08', '2026-01-11'],
    [absolute('week', 1, '2026-01-07', [6, 0, 3]), '2026-01-11', '2026-01-12'],
    [absolute('week', 2, '2026-01-07', [0]), '2026-01-13', '2026-01-19'],
    [absolute('week', 2, '2025-12-22', [0]), '2025-12-29', '2026-01-05'],
    [absolute('week', 2, '2026-01-07', [3]), '2025-12-25', '2026-01-08'],
    [absolute('year', 2, '2026-08-03'), '2027-10-01', '2028-08-03'],
    [absolute('year', 2, '2026-08-03'), '2028-08-03', '2030-08-03'],
    [absolute('year', 1, '2024-02-29'), '2027-02-28', '2028-02-29'],
  ];
  for (const [rule, current, expected] of cases) assert.equal(nextDate(current, rule), expected);
});

test('absolute monthly anchors clamp short months, resume original day, and avoid duplicate clamped dates', () => {
  const rule = absolute('month', 1, '2026-01-20', [30, 0, 14]);
  assert.equal(normalizeRule(rule).reference, '2026-01-01');
  assert.deepEqual(normalizeRule(rule).anchors, [0, 14, 30]);
  for (const [current, expected] of [['2026-01-01', '2026-01-15'], ['2026-01-15', '2026-01-31'], ['2026-01-31', '2026-02-01']]) {
    assert.equal(nextDate(current, rule), expected);
  }
  const monthEnd = absolute('month', 1, '2026-01-01', [30]);
  assert.equal(nextDate('2026-01-31', monthEnd), '2026-02-28');
  assert.equal(nextDate('2026-02-28', monthEnd), '2026-03-31');
  assert.equal(nextDate('2026-02-15', absolute('month', 2, '2026-01-20', [9])), '2026-03-10');
  assert.deepEqual(virtualDates('2026-02-27', absolute('month', 1, '2026-01-01', [27, 28, 29, 30]), '2026-03-01'), ['2026-02-28']);
});

test('relative projection exposes one date even beyond the horizon; absolute projection honors inclusive horizon and cutoff', () => {
  assert.deepEqual(virtualDates('2026-01-01', relative('day', 10), '2026-01-02'), ['2026-01-11']);
  const rule = absolute('day', 3, '2026-01-01');
  assert.deepEqual(virtualDates('2026-01-01', rule, '2026-01-10'), ['2026-01-04', '2026-01-07', '2026-01-10']);
  assert.deepEqual(virtualDates('2026-01-01', { ...rule, repeatUntil: '2026-01-07' }, '2026-01-31'), ['2026-01-04', '2026-01-07']);
  assert.deepEqual(virtualDates('2026-01-01', { ...relative('day', 2), repeatUntil: '2026-01-02' }, '2026-02-01'), []);
  assert.throws(() => virtualDates('2026-01-01', absolute('day', 1, '2026-01-01'), '2026-01-10', 3), invalid);
});

test('invalid intervals, anchors, and absolute references are rejected rather than guessed', () => {
  const rules: Rule[] = [
    relative('day', 0), relative('day', -1), relative('day', 1.5), relative('day', Infinity),
    absolute('week', 1, '2026-01-01', []), absolute('month', 1, '2026-01-01', []),
    absolute('week', 1, '2026-01-01', [-1, 0]), absolute('week', 1, '2026-01-01', [7]),
    absolute('month', 1, '2026-01-01', [31]), absolute('week', 1, '2026-01-01', [0, 0]),
    absolute('day', 1, '2026-01-01', [0]), absolute('year', 1, '2026-01-01', [0]),
    { mode: 'absolute', unit: 'day', interval: 1 },
  ];
  for (const rule of rules) assert.throws(() => normalizeRule(rule), invalid);
  assert.throws(() => nextDate('2026-02-30', relative()));
});

test('CloudKit anchors reproduce actual Foundation NSKeyedArchiver bytes', () => {
  // Produced by NSKeyedArchiver.archivedData(withRootObject: [0, 4, 30] as NSArray, requiringSecureCoding: true).
  const native = 'YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGmCwwUFRYXVSRudWxs0g0ODxNaTlMub2JqZWN0c1YkY2xhc3OjEBESgAKAA4AEgAUQABAEEB7SGBkaG1okY2xhc3NuYW1lWCRjbGFzc2VzV05TQXJyYXmiGhxYTlNPYmplY3QIERokKTI3SUxRU1pgZXB3e31/gYOFh4mOmaKqrQAAAAAAAAEBAAAAAAAAAB0AAAAAAAAAAAAAAAAAAAC2';
  assert.deepEqual(decodeAnchors(native), [0, 4, 30]);
  assert.equal(encodeAnchors([0, 4, 30]), native);
  for (const anchors of [[], [0], [0, 2, 4, 6], [0, 14, 30]]) assert.deepEqual(decodeAnchors(encodeAnchors(anchors)), anchors);
});

test('anchor decoding rejects malformed/foreign archives and out-of-range values', () => {
  assert.deepEqual(decodeAnchors(null), []);
  for (const encoded of ['garbage', '', Buffer.from('[0,4]').toString('base64'), Buffer.from(createPlist({ anchors: [0, 4] })).toString('base64')]) {
    assert.throws(() => decodeAnchors(encoded), invalid);
  }
  assert.throws(() => encodeAnchors([-1]), invalid);
  assert.throws(() => encodeAnchors([31]), invalid);
});

test('rule storage uses CloudKit timestamp/bytes fields and restores calendar dates', () => {
  const rule = absolute('week', 2, '2026-01-07', [4, 0]);
  const template = record('CD_RecurrenceTemplate', TEMPLATE, {});
  Object.assign(template.fields, ruleFields({ ...rule, repeatUntil: '2026-02-01' }, ZONE));
  assert.equal(template.fields.CD_anchors.type, 'BYTES');
  assert.equal(template.fields.CD_reference.type, 'TIMESTAMP');
  assert.equal(template.fields.CD_reference.value, Date.parse('2026-01-05T08:00:00Z'));
  assert.deepEqual(ruleFromRecord(template, ZONE), { mode: 'absolute', unit: 'week', interval: 2, anchors: [0, 4], reference: '2026-01-05', repeatUntil: '2026-02-01' });
});

test('starting a recurrence copies current content/project and extracts wall-clock seconds', () => {
  const todo = record('CD_Todo', TASK, {
    title: 'Standup', notes: 'Team notes', order: 'i', project: 'cloud-project', includesTime: 1,
    scheduledDate: Date.parse('2026-07-01T16:15:30Z'), endDate: Date.parse('2026-07-01T16:45:00Z'),
  });
  const { template, taskFields } = createTemplatePlan(todo, relative(), TEMPLATE, NOW, ZONE);
  assert.equal(template.recordType, 'CD_RecurrenceTemplate');
  assert.equal(value(template, 'entityName'), 'RecurrenceTemplate');
  assert.equal(value(template, 'currentItemID'), TASK);
  assert.equal(value(template, 'currentSequence'), 0);
  assert.equal(value(template, 'title'), 'Standup');
  assert.equal(value(template, 'notes'), 'Team notes');
  assert.equal(value(template, 'project'), 'cloud-project');
  assert.equal(value(template, 'startTimeSeconds'), 9 * 3600 + 15 * 60 + 30);
  assert.equal(value(template, 'endTimeSeconds'), 9 * 3600 + 45 * 60);
  assert.equal(taskFields.CD_recurrenceTemplate.value, template.recordName);
  assert.equal(taskFields.CD_recurrenceSequence.value, 0);
  assert.equal(taskFields.CD_modifiedAt.value, NOW);
  assert.equal(value(todo, 'recurrenceTemplate'), null);
});

test('a recurrence cannot start on completed/repeating tasks or a timed task spanning midnight', () => {
  for (const extra of [
    { completedAt: NOW }, { recurrenceSequence: 0 }, { recurrenceTemplate: 'already-linked' },
    { includesTime: 1, scheduledDate: Date.parse('2026-07-01T23:30:00Z'), endDate: Date.parse('2026-07-02T07:30:00Z') },
  ] as Record<string, CloudKitValue>[]) {
    const todo = record('CD_Todo', TASK, { title: 'Task', order: 'i', scheduledDate: NOW, includesTime: 0, ...extra });
    assert.throws(() => createTemplatePlan(todo, relative(), TEMPLATE, NOW, ZONE), invalid);
  }
});

test('rule-only editing preserves future times; clearing time also clears the future end', () => {
  const { template } = fixture();
  template.fields.CD_startTimeSeconds = { value: 9 * 3600 };
  template.fields.CD_endTimeSeconds = { value: 10 * 3600 };
  const ruleEdit = editTemplatePlan(template, { rule: relative('week', 2) }, NOW, ZONE);
  assert.equal(ruleEdit.record.fields.CD_startTimeSeconds, undefined);
  assert.equal(ruleEdit.record.fields.CD_endTimeSeconds, undefined);
  assert.equal(ruleEdit.record.fields.CD_interval.value, 2);
  const removeTime = editTemplatePlan(template, { time: null }, NOW, ZONE);
  assert.equal(removeTime.record.fields.CD_startTimeSeconds.value, null);
  assert.equal(removeTime.record.fields.CD_endTimeSeconds.value, null);
  assert.throws(() => editTemplatePlan(template, { time: null, endTime: '10:00' }, NOW, ZONE), invalid);
});

test('next occurrence uses template wall time across DST and picks next valid time in a gap', () => {
  const { template } = fixture();
  template.fields.CD_startTimeSeconds = { value: 9 * 3600 };
  template.fields.CD_endTimeSeconds = { value: 10 * 3600 };
  assert.equal(occurrenceSchedule(template, '2026-03-07', ZONE).CD_scheduledDate.value, Date.parse('2026-03-07T17:00:00Z'));
  assert.equal(occurrenceSchedule(template, '2026-03-08', ZONE).CD_scheduledDate.value, Date.parse('2026-03-08T16:00:00Z'));
  template.fields.CD_startTimeSeconds = { value: 2 * 3600 + 30 * 60 };
  assert.equal(occurrenceSchedule(template, '2026-03-08', ZONE).CD_scheduledDate.value, Date.parse('2026-03-08T10:00:00Z'));
});

test('completion retains current history and creates one successor from future template values', () => {
  const { todo, template, history } = fixture(relative('day', 2));
  const original = structuredClone({ todo, template, history });
  const { operations, next } = advancePlan(todo, template, [todo, history], 'complete', NOW, ZONE);
  assert.ok(next);
  assert.equal(value(next, 'title'), 'Future title');
  assert.equal(value(next, 'notes'), 'Future notes');
  assert.equal(value(next, 'scheduledDate'), Date.parse('2026-07-03T07:00:00Z'));
  assert.equal(value(next, 'order'), 'r');
  assert.equal(value(next, 'projectOrder'), 'c');
  assert.equal(value(next, 'project'), 'cloud-project');
  assert.equal(value(next, 'recurrenceSequence'), 2);
  assert.equal(value(next, 'recurrenceTemplate'), template.recordName);
  assert.notEqual(value(next, 'id'), TASK);
  assert.notEqual(value(next, 'id'), value(next, 'syncRecordID'));
  const updatedTemplate = operations.find(operation => operation.record.recordName === template.recordName)!;
  assert.equal(updatedTemplate.record.fields.CD_currentItemID.value, value(next, 'id'));
  assert.equal(updatedTemplate.record.fields.CD_currentSequence.value, 2);
  const completed = operations.find(operation => operation.record.recordName === todo.recordName)!;
  assert.equal(completed.record.fields.CD_completedAt.value, NOW);
  assert.equal(completed.record.fields.CD_title, undefined);
  assert.equal(operations.length, 3);
  assert.deepEqual({ todo, template, history }, original);
});

test('deleting the current occurrence advances once; deleting completed history leaves the series alone', () => {
  const { todo, template, history } = fixture();
  const currentDeletion = advancePlan(todo, template, [todo, history], 'delete', NOW, ZONE);
  assert.ok(currentDeletion.next);
  assert.equal(currentDeletion.operations.find(operation => operation.record.recordName === todo.recordName)!.operationType, 'delete');
  const historicalDeletion = advancePlan(history, template, [todo, history], 'delete', NOW, ZONE);
  assert.equal(historicalDeletion.next, null);
  assert.equal(historicalDeletion.operations.length, 1);
  assert.equal(historicalDeletion.operations[0].record.recordName, history.recordName);
});

test('reaching the inclusive cutoff terminates recurrence, detaches history, and completes or deletes current', () => {
  for (const action of ['complete', 'delete'] as const) {
    const { todo, template, history } = fixture({ ...relative(), repeatUntil: '2026-07-01' });
    const result = advancePlan(todo, template, [todo, history], action, NOW, ZONE);
    assert.equal(result.next, null);
    assert.equal(result.operations.length, 3);
    const current = result.operations.find(operation => operation.record.recordName === todo.recordName)!;
    assert.equal(current.operationType, action === 'delete' ? 'delete' : 'update');
    if (action === 'complete') {
      assert.equal(current.record.fields.CD_completedAt.value, NOW);
      assert.equal(current.record.fields.CD_recurrenceTemplate.value, null);
      assert.equal(current.record.fields.CD_recurrenceSequence.value, null);
    }
    const previous = result.operations.find(operation => operation.record.recordName === history.recordName)!;
    assert.equal(previous.record.fields.CD_recurrenceTemplate.value, null);
    assert.equal(previous.record.fields.CD_completedAt, undefined);
    assert.equal(result.operations.find(operation => operation.record.recordName === template.recordName)!.operationType, 'delete');
  }
});

test('stopping recurrence preserves both the current occurrence and completed history', () => {
  const { todo, template, history } = fixture();
  const operations = stopPlan(template, [todo, history], NOW);
  assert.equal(operations.filter(operation => operation.operationType === 'delete').length, 1);
  assert.equal(operations.at(-1)!.record.recordName, template.recordName);
  for (const operation of operations.slice(0, 2)) {
    assert.deepEqual(Object.keys(operation.record.fields).sort(), ['CD_modifiedAt', 'CD_recurrenceSequence', 'CD_recurrenceTemplate']);
    assert.equal(operation.record.fields.CD_recurrenceTemplate.value, null);
  }
});

test('advancement refuses stale sequences, duplicate active occurrences, already-completed tasks and counter overflow', () => {
  const cases = [
    (todo: CloudKitRecord, template: CloudKitRecord) => { template.fields.CD_currentItemID.value = HISTORY; },
    (todo: CloudKitRecord) => { todo.fields.CD_recurrenceSequence.value = 4; },
    (todo: CloudKitRecord) => { todo.fields.CD_completedAt = { value: NOW }; },
    (todo: CloudKitRecord, template: CloudKitRecord) => { template.fields.CD_currentSequence.value = Number.MAX_SAFE_INTEGER; todo.fields.CD_recurrenceSequence.value = Number.MAX_SAFE_INTEGER; },
  ];
  for (const mutate of cases) {
    const { todo, template } = fixture();
    mutate(todo, template);
    assert.throws(() => advancePlan(todo, template, [todo], 'complete', NOW, ZONE), invalid);
  }
  const { todo, template } = fixture();
  const duplicate = { ...todo, recordName: 'second-active' };
  assert.throws(() => advancePlan(todo, template, [todo, duplicate], 'complete', NOW, ZONE), invalid);
});
