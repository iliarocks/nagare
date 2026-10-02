import { Temporal } from '@js-temporal/polyfill';
import { NagareError } from './records.js';
import { field, number, value, type Fields } from './records.js';
import type { CloudKitRecord } from './cloudkit.js';

export interface Schedule { date: string; time?: string | null; endTime?: string | null }

export function day(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new NagareError('INVALID_SCHEDULE', 'Use a date in YYYY-MM-DD form.');
  return Temporal.PlainDate.from(value, { overflow: 'reject' });
}

export function clockTime(value: string) {
  if (!/^\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?$/.test(value)) throw new NagareError('INVALID_SCHEDULE', 'Use a time in HH:mm or HH:mm:ss form.');
  return Temporal.PlainTime.from(value, { overflow: 'reject' });
}

// Calendar.date(bySettingHour:) picks the first occurrence of repeated time,
// and the next valid instant when a daylight-saving transition skips that time.
export function calendarTime(date: Temporal.PlainDate, time: Temporal.PlainTime, zone: string): number {
  const requested = date.toPlainDateTime(time);
  const earlier = requested.toZonedDateTime(zone, { disambiguation: 'earlier' });
  if (earlier.toPlainDateTime().equals(requested)) return earlier.epochMilliseconds;
  let lower = earlier.epochMilliseconds;
  let upper = requested.toZonedDateTime(zone, { disambiguation: 'later' }).epochMilliseconds;
  while (upper - lower > 1) {
    const middle = Math.floor((lower + upper) / 2);
    const local = Temporal.Instant.fromEpochMilliseconds(middle).toZonedDateTimeISO(zone).toPlainDateTime();
    if (Temporal.PlainDateTime.compare(local, requested) < 0) lower = middle;
    else upper = middle;
  }
  return upper;
}


export function localDate(timestamp: number, zone: string): string {
  return Temporal.Instant.fromEpochMilliseconds(timestamp).toZonedDateTimeISO(zone).toPlainDate().toString();
}

export function localTime(timestamp: number, zone: string): string {
  return Temporal.Instant.fromEpochMilliseconds(timestamp).toZonedDateTimeISO(zone).toPlainTime().toString({ smallestUnit: 'minute' });
}

export function scheduleFields(input: Schedule, zone: string, existing?: CloudKitRecord): Fields {
  const date = day(input.date);
  if (input.time === '' || input.endTime === '') throw new NagareError('INVALID_SCHEDULE', 'Use null to remove a time.');
  const oldStart = existing ? number(existing, 'scheduledDate') : null;
  const oldTime = oldStart === null ? null : Temporal.Instant.fromEpochMilliseconds(oldStart).toZonedDateTimeISO(zone).toPlainTime().round({ smallestUnit: 'second', roundingMode: 'trunc' }).toString();
  const time = input.time === undefined ? value(existing, 'includesTime') === 1 ? oldTime : null : input.time;
  const start = time ? calendarTime(date, clockTime(time), zone) : date.toZonedDateTime(zone).epochMilliseconds;
  let end: number | null = null;
  if (time && input.endTime) end = calendarTime(date, clockTime(input.endTime), zone);
  else if (!time && input.endTime) throw new NagareError('INVALID_SCHEDULE', 'An end time requires a start time.');
  else if (time && input.endTime === undefined && existing && value(existing, 'endDate') !== null) end = start + number(existing, 'endDate') - oldStart!;
  // Native date movement preserves stored durations, including old zero or
  // negative ranges. Validate new times without blocking unrelated rollover.
  if (end !== null && end <= start && (!existing || input.time !== undefined || input.endTime !== undefined)) {
    throw new NagareError('INVALID_SCHEDULE', 'The end time must follow the start time.');
  }
  return { CD_scheduledDate: field(start, 'TIMESTAMP'), CD_includesTime: field(time ? 1 : 0, 'INT64'), CD_endDate: field(end, 'TIMESTAMP') };
}
