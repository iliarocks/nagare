import assert from 'node:assert/strict';
import test from 'node:test';
import type { CloudKitRecord } from '../src/cloudkit.js';
import { calendarTime, clockTime, day, scheduleFields } from '../src/calendar.js';
import { field } from '../src/records.js';

const ZONE = 'America/Los_Angeles';

function timed(start: string, end: string): CloudKitRecord {
  return { recordType: 'CD_Todo', recordName: 'task', fields: {
    CD_scheduledDate: field(Date.parse(start)), CD_endDate: field(Date.parse(end)), CD_includesTime: field(1),
  } };
}

test('calendar time matches Foundation nextTime and first repeated-time policies', () => {
  // Expected instants verified with Calendar.date(bySettingHour:minute:second:of:).
  assert.equal(calendarTime(day('2026-03-08'), clockTime('02:30:45'), ZONE), Date.parse('2026-03-08T10:00:00Z'));
  assert.equal(calendarTime(day('2026-11-01'), clockTime('01:30'), ZONE), Date.parse('2026-11-01T08:30:00Z'));
});

test('moving a timed task through a clock change keeps duration and native second precision', () => {
  const task = timed('2026-03-07T10:30:45.125Z', '2026-03-07T11:30:45.125Z');
  const moved = scheduleFields({ date: '2026-03-08' }, ZONE, task);
  assert.equal(moved.CD_scheduledDate.value, Date.parse('2026-03-08T10:00:00Z'));
  assert.equal(moved.CD_endDate.value, Date.parse('2026-03-08T11:00:00Z'));
  assert.equal(moved.CD_includesTime.value, 1);

  const ordinary = scheduleFields({ date: '2026-03-09' }, ZONE, task);
  assert.equal(ordinary.CD_scheduledDate.value, Date.parse('2026-03-09T09:30:45Z'));
  assert.equal(ordinary.CD_endDate.value, Date.parse('2026-03-09T10:30:45Z'));
});

test('all-day schedules use local midnight and removing time clears the end', () => {
  const task = timed('2026-03-07T10:30:00Z', '2026-03-07T11:30:00Z');
  const cleared = scheduleFields({ date: '2026-03-09', time: null }, ZONE, task);
  assert.equal(cleared.CD_scheduledDate.value, Date.parse('2026-03-09T07:00:00Z'));
  assert.equal(cleared.CD_includesTime.value, 0);
  assert.equal(cleared.CD_endDate.value, null);
  assert.equal(scheduleFields({ date: '2026-03-09' }, 'Asia/Tokyo').CD_scheduledDate.value, Date.parse('2026-03-08T15:00:00Z'));
});

test('clearing only the end time preserves the existing start and rejects impossible schedules', () => {
  const task = timed('2026-03-07T10:30:00Z', '2026-03-07T11:30:00Z');
  const cleared = scheduleFields({ date: '2026-03-07', endTime: null }, ZONE, task);
  assert.equal(cleared.CD_scheduledDate.value, Date.parse('2026-03-07T10:30:00Z'));
  assert.equal(cleared.CD_endDate.value, null);
  for (const schedule of [
    { date: '2026-02-30' },
    { date: '2026-03-09', endTime: '10:00' },
    { date: '2026-03-09', time: '12:00', endTime: '11:00' },
    { date: '2026-03-09', time: '' },
  ]) assert.throws(() => scheduleFields(schedule, ZONE));
});
