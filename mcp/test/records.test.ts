import assert from 'node:assert/strict';
import test from 'node:test';
import type { CloudKitRecord } from '../src/cloudkit.js';
import { deletion, field, mergeMutations, moveOrder, update, value } from '../src/records.js';

function record(index: number, order: string): CloudKitRecord {
  const id = String(index).padStart(8, '0') + '-1111-4111-8111-111111111111';
  return { recordType: 'CD_Todo', recordName: id, recordChangeTag: 'read-revision', fields: {
    CD_id: field(id), CD_order: field(order), CD_title: field('Task'),
  } };
}

test('atomic plans combine rollover and command fields without mutating either input; deletion wins', () => {
  const todo = record(1, 'a');
  const rollover = update(todo, { CD_scheduledDate: field(100), CD_order: field('z') });
  const complete = update(todo, { CD_completedAt: field(200) });
  const original = structuredClone([rollover, complete]);
  const merged = mergeMutations([rollover, complete]);
  assert.equal(merged.length, 1);
  assert.equal(merged[0].record.recordChangeTag, 'read-revision');
  assert.equal(value(merged[0].record, 'scheduledDate'), 100);
  assert.equal(value(merged[0].record, 'completedAt'), 200);
  assert.deepEqual([rollover, complete], original);
  assert.equal(mergeMutations([rollover, deletion(todo), complete])[0].operationType, 'delete');
});

test('a move with no fractional space repairs only its destination while keeping selected order', () => {
  const first = record(1, '0');
  const moved = [record(2, 'y'), record(3, 'z')];
  const repairs = moveOrder([first], moved, first.recordName, 'order', 100);
  assert.deepEqual(repairs.map(operation => operation.record.recordName), [moved[0].recordName, moved[1].recordName, first.recordName]);
  // These are FractionalIndex.rebalancedKeys(count: 3) in the native app.
  assert.deepEqual(repairs.map(operation => value(operation.record, 'order')), ['8zzzzzzzzzzz', 'hzzzzzzzzzzy', 'qzzzzzzzzzzx']);
  assert.equal(value(first, 'order'), '0');
  assert.deepEqual(moved.map(item => value(item, 'order')), ['y', 'z']);
});
