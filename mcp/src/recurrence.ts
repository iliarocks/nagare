import { Temporal } from '@js-temporal/polyfill';
import { Buffer } from 'node:buffer';
import createPlist from 'bplist-creator';
import { parseBuffer, UID } from 'bplist-parser';
import type { CloudKitRecord } from './cloudkit.js';
import { calendarTime, clockTime, day, localDate } from './calendar.js';
import { deletion, field, id, mergeMutations, NagareError, number, text, update, uuid, validOrder, value } from './records.js';
import type { Fields, Mutation } from './records.js';

export interface Rule {
  mode: 'relative' | 'absolute';
  unit: 'day' | 'week' | 'month' | 'year';
  interval: number;
  anchors?: number[];
  reference?: string | null;
  repeatUntil?: string | null;
}

export type NormalizedRule = Rule & { anchors: number[]; reference: string | null; repeatUntil: string | null };

export function normalizeRule(input: Rule): NormalizedRule {
  if (!['relative', 'absolute'].includes(input.mode) || !['day', 'week', 'month', 'year'].includes(input.unit)) {
    throw invalid('Unknown recurrence mode or unit.');
  }
  if (!Number.isSafeInteger(input.interval) || input.interval <= 0) throw invalid('The repeat interval must be a positive integer.');
  const repeatUntil = input.repeatUntil == null ? null : day(input.repeatUntil).toString();
  if (input.mode === 'relative') return { ...input, anchors: [], reference: null, repeatUntil };
  if (!input.reference) throw invalid('An absolute recurrence requires a reference date.');
  const anchors = [...(input.anchors ?? [])].sort((a, b) => a - b);
  if (input.unit === 'day' || input.unit === 'year') {
    if (anchors.length) throw invalid('Daily and yearly repeats do not accept anchors.');
  } else {
    const maximum = input.unit === 'week' ? 6 : 30;
    if (!anchors.length || anchors.some(anchor => !Number.isInteger(anchor) || anchor < 0 || anchor > maximum)
      || new Set(anchors).size !== anchors.length) throw invalid(`Use distinct anchors from 0 through ${maximum}.`);
  }
  const reference = periodStart(day(input.reference), input.unit).toString();
  return { ...input, anchors, reference, repeatUntil };
}

export function nextDate(after: string, input: Rule): string {
  const rule = normalizeRule(input);
  const current = day(after);
  if (rule.mode === 'relative') return add(current, rule.interval, rule.unit).toString();
  const reference = day(rule.reference!);
  if (rule.unit === 'day') {
    if (compare(current, reference) < 0) return reference.toString();
    const elapsed = reference.until(current).days;
    return reference.add({ days: (Math.floor(elapsed / rule.interval) + 1) * rule.interval }).toString();
  }
  if (rule.unit === 'year') {
    if (compare(current, reference) < 0) return reference.toString();
    const elapsed = reference.until(current, { largestUnit: 'years' }).years;
    let periods = Math.max(Math.floor(elapsed / rule.interval), 0) + 1;
    let candidate = reference.add({ years: periods * rule.interval });
    while (compare(candidate, current) <= 0) candidate = reference.add({ years: ++periods * rule.interval });
    return candidate.toString();
  }
  const currentPeriod = periodStart(current, rule.unit);
  if (compare(currentPeriod, reference) < 0) return anchored(reference, rule.anchors[0], rule.unit).toString();
  const elapsed = rule.unit === 'week'
    ? reference.until(currentPeriod).days / 7
    : reference.until(currentPeriod, { largestUnit: 'months' }).months;
  const remainder = elapsed % rule.interval;
  if (remainder === 0) {
    for (const anchor of rule.anchors) {
      const candidate = anchored(currentPeriod, anchor, rule.unit);
      if (compare(candidate, current) > 0) return candidate.toString();
    }
  }
  const nextPeriod = add(currentPeriod, remainder === 0 ? rule.interval : rule.interval - remainder, rule.unit);
  return anchored(nextPeriod, rule.anchors[0], rule.unit).toString();
}

// Relative rules show one next occurrence even beyond the display horizon.
export function virtualDates(after: string, input: Rule, horizon: string, maximumCount = 10_000): string[] {
  if (!Number.isSafeInteger(maximumCount) || maximumCount <= 0) throw invalid('The projection limit must be positive.');
  const rule = normalizeRule(input);
  const last = day(horizon).toString();
  let candidate = nextDate(after, rule);
  if (!permits(rule, candidate)) return [];
  if (rule.mode === 'relative') return [candidate];
  const dates: string[] = [];
  while (candidate <= last && permits(rule, candidate)) {
    if (dates.length === maximumCount) throw invalid(`The recurrence exceeds ${maximumCount} projected occurrences.`);
    dates.push(candidate);
    const next = nextDate(candidate, rule);
    if (next <= candidate) throw invalid('The recurrence did not advance.');
    candidate = next;
  }
  return dates;
}

export function ruleFromRecord(template: CloudKitRecord, zone: string): NormalizedRule {
  const mode = text(template, 'modeRawValue') as Rule['mode'];
  return normalizeRule({
    mode,
    unit: text(template, 'unitRawValue') as Rule['unit'],
    interval: number(template, 'interval'),
    anchors: mode === 'absolute' ? decodeAnchors(text(template, 'anchors')) : [],
    reference: value(template, 'reference') == null ? null : localDate(number(template, 'reference'), zone),
    repeatUntil: value(template, 'repeatUntil') == null ? null : localDate(number(template, 'repeatUntil'), zone),
  });
}

export function ruleFields(input: Rule, zone: string): Fields {
  const rule = normalizeRule(input);
  const midnight = (date: string | null) => date === null ? null : day(date).toZonedDateTime(zone).epochMilliseconds;
  return {
    CD_modeRawValue: field(rule.mode), CD_unitRawValue: field(rule.unit), CD_interval: field(rule.interval, 'INT64'),
    CD_anchors: field(encodeAnchors(rule.anchors), 'BYTES'), CD_anchors_ckAsset: field(null),
    CD_reference: field(midnight(rule.reference), 'TIMESTAMP'), CD_repeatUntil: field(midnight(rule.repeatUntil), 'TIMESTAMP'),
  };
}

// SwiftData stores [Int] as an NSKeyedArchiver NSArray, including when mirrored
// into CloudKit BYTES. These bytes were cross-checked with Foundation's encoder.
export function encodeAnchors(anchors: number[]): string {
  validateAnchors(anchors);
  return Buffer.from(createPlist({
    $version: 100000, $archiver: 'NSKeyedArchiver', $top: { root: new UID(1) },
    $objects: ['$null', { 'NS.objects': anchors.map((_, index) => new UID(index + 2)), $class: new UID(anchors.length + 2) },
      ...anchors, { $classname: 'NSArray', $classes: ['NSArray', 'NSObject'] }],
  })).toString('base64');
}

export function decodeAnchors(encoded: string | null): number[] {
  if (encoded === null) return [];
  try {
    if (encoded.length > 16_384 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) throw invalid('Invalid anchor encoding.');
    const [archive] = parseBuffer(Buffer.from(encoded, 'base64'));
    if (archive?.$archiver !== 'NSKeyedArchiver' || !Array.isArray(archive.$objects)) throw invalid('Invalid anchor archive.');
    const objects: unknown[] = archive.$objects;
    const resolve = (reference: unknown): unknown => reference instanceof UID ? objects[reference.UID] : undefined;
    const root = resolve(archive.$top?.root) as { 'NS.objects'?: unknown[]; $class?: UID } | undefined;
    const cls = resolve(root?.$class) as { $classname?: string } | undefined;
    if (!['NSArray', 'NSMutableArray'].includes(cls?.$classname ?? '') || !Array.isArray(root?.['NS.objects'])) throw invalid('Invalid anchor array.');
    const anchors = root['NS.objects'].map(resolve);
    validateAnchors(anchors);
    return anchors;
  } catch {
    throw invalid('The recurrence anchors could not be decoded.');
  }
}

export function createTemplatePlan(todo: CloudKitRecord, rule: Rule, templateId: string, now: number, zone: string) {
  if (value(todo, 'recurrenceTemplate') != null || value(todo, 'recurrenceSequence') != null) throw invalid('This task already repeats.');
  if (value(todo, 'completedAt') != null) throw invalid('A completed task cannot start a recurrence.');
  if (!validOrder(text(todo, 'order'))) throw invalid('The task has an invalid saved position.');
  const template: CloudKitRecord = {
    recordType: 'CD_RecurrenceTemplate', recordName: `CD_RecurrenceTemplate_${uuid(templateId)}`,
    fields: {
      CD_entityName: field('RecurrenceTemplate'), CD_id: field(uuid(templateId)),
      CD_syncRecordID: field(crypto.randomUUID().toUpperCase()), CD_itemTypeRawValue: field('todo'),
      CD_title: field(text(todo, 'title') ?? ''), CD_notes: field(text(todo, 'notes')),
      CD_project: field(text(todo, 'project')), CD_createdAt: field(now, 'TIMESTAMP'), CD_modifiedAt: field(now, 'TIMESTAMP'),
      CD_currentItemID: field(id(todo)), CD_currentSequence: field(0, 'INT64'),
      ...ruleFields(rule, zone), ...wallTimeFields(todo, zone),
    },
  };
  return { template, taskFields: {
    CD_recurrenceTemplate: field(template.recordName), CD_recurrenceSequence: field(0, 'INT64'), CD_modifiedAt: field(now, 'TIMESTAMP'),
  } };
}

export function editTemplatePlan(
  template: CloudKitRecord,
  changes: { rule?: Rule; time?: string | null; endTime?: string | null },
  now: number,
  zone: string,
): Mutation {
  const fields: Fields = { CD_modifiedAt: field(now, 'TIMESTAMP') };
  if (changes.rule) Object.assign(fields, ruleFields(changes.rule, zone));
  const start = changes.time === undefined ? optionalSeconds(template, 'startTimeSeconds') : seconds(changes.time);
  const end = changes.endTime === undefined
    ? start === null ? null : optionalSeconds(template, 'endTimeSeconds')
    : seconds(changes.endTime);
  validateTimes(start, end);
  if (changes.time !== undefined) fields.CD_startTimeSeconds = field(start, 'INT64');
  if (changes.endTime !== undefined || changes.time === null) fields.CD_endTimeSeconds = field(end, 'INT64');
  return update(template, fields);
}

export function occurrenceSchedule(template: CloudKitRecord, date: string, zone: string): Fields {
  const start = optionalSeconds(template, 'startTimeSeconds');
  const end = optionalSeconds(template, 'endTimeSeconds');
  validateTimes(start, end);
  const when = day(date);
  const at = (seconds: number) => calendarTime(when, Temporal.PlainTime.from({
    hour: Math.floor(seconds / 3600), minute: Math.floor(seconds % 3600 / 60), second: seconds % 60,
  }), zone);
  return {
    CD_scheduledDate: field(start === null ? when.toZonedDateTime(zone).epochMilliseconds : at(start), 'TIMESTAMP'),
    CD_includesTime: field(start === null ? 0 : 1, 'INT64'), CD_endDate: field(end === null ? null : at(end), 'TIMESTAMP'),
  };
}

export function advancePlan(
  todo: CloudKitRecord,
  template: CloudKitRecord,
  allTodos: CloudKitRecord[],
  action: 'complete' | 'delete',
  now: number,
  zone: string,
): { operations: Mutation[]; next: CloudKitRecord | null } {
  if (value(todo, 'completedAt') != null) {
    if (action === 'delete') return { operations: [deletion(todo)], next: null };
    throw invalid('This occurrence is already completed.');
  }
  const sequence = number(template, 'currentSequence');
  const active = allTodos.filter(record => value(record, 'recurrenceTemplate') === template.recordName && value(record, 'completedAt') == null);
  if (uuid(text(template, 'currentItemID') ?? '') !== id(todo)
    || value(todo, 'recurrenceSequence') !== sequence || active.length !== 1 || active[0].recordName !== todo.recordName) {
    throw invalid('The recurrence must have exactly one matching current occurrence before it can advance.');
  }
  if (!validOrder(text(todo, 'order'))) throw invalid('The current occurrence has an invalid saved position.');
  const rule = ruleFromRecord(template, zone);
  const date = nextDate(localDate(number(todo, 'scheduledDate'), zone), rule);
  const operations: Mutation[] = [];
  let next: CloudKitRecord | null = null;
  if (permits(rule, date)) {
    if (!Number.isSafeInteger(sequence) || sequence < 0 || sequence >= Number.MAX_SAFE_INTEGER) throw invalid('The occurrence counter cannot advance further.');
    const nextId = crypto.randomUUID().toUpperCase();
    next = {
      recordType: 'CD_Todo', recordName: `CD_Todo_${nextId}`,
      fields: {
        CD_entityName: field('Todo'), CD_id: field(nextId), CD_syncRecordID: field(crypto.randomUUID().toUpperCase()),
        CD_title: field(text(template, 'title') ?? ''), CD_notes: field(text(template, 'notes')),
        CD_createdAt: field(now, 'TIMESTAMP'), CD_modifiedAt: field(now, 'TIMESTAMP'),
        CD_project: field(text(template, 'project')), CD_order: field(text(todo, 'order')),
        CD_projectOrder: field(text(todo, 'projectOrder')),
        CD_recurrenceTemplate: field(template.recordName), CD_recurrenceSequence: field(sequence + 1, 'INT64'),
        ...occurrenceSchedule(template, date, zone),
      },
    };
    operations.push({ operationType: 'create', record: next }, update(template, {
      CD_currentItemID: field(nextId), CD_currentSequence: field(sequence + 1, 'INT64'), CD_modifiedAt: field(now, 'TIMESTAMP'),
    }));
  } else operations.push(...stopPlan(template, allTodos, now));
  operations.push(action === 'delete' ? deletion(todo) : update(todo, {
    CD_completedAt: field(now, 'TIMESTAMP'), CD_modifiedAt: field(now, 'TIMESTAMP'),
  }));
  return { operations: mergeMutations(operations), next };
}

// Removing Repeat retains the current task and completed history as ordinary tasks.
export function stopPlan(template: CloudKitRecord, allTodos: CloudKitRecord[], now: number): Mutation[] {
  return [...allTodos.filter(todo => value(todo, 'recurrenceTemplate') === template.recordName).map(todo => update(todo, {
    CD_recurrenceTemplate: field(null), CD_recurrenceSequence: field(null), CD_modifiedAt: field(now, 'TIMESTAMP'),
  })), deletion(template)];
}

function wallTimeFields(todo: CloudKitRecord, zone: string): Fields {
  let start: number | null = null;
  let end: number | null = null;
  if (value(todo, 'includesTime') === 1) {
    const startDate = number(todo, 'scheduledDate');
    const wallTime = (timestamp: number) => {
      const time = Temporal.Instant.fromEpochMilliseconds(timestamp).toZonedDateTimeISO(zone);
      return time.hour * 3600 + time.minute * 60 + time.second;
    };
    start = wallTime(startDate);
    if (value(todo, 'endDate') != null) {
      const endDate = number(todo, 'endDate');
      if (localDate(startDate, zone) !== localDate(endDate, zone)) throw invalid('Repeating tasks must start and end on the same day.');
      end = wallTime(endDate);
    }
  }
  return { CD_startTimeSeconds: field(start, 'INT64'), CD_endTimeSeconds: field(end, 'INT64') };
}

function validateTimes(start: number | null, end: number | null) {
  if (start === null && end !== null) throw invalid('An end time requires a start time.');
  for (const time of [start, end]) if (time !== null && (!Number.isInteger(time) || time < 0 || time >= 86_400)) throw invalid('Invalid recurrence time.');
}

function optionalSeconds(record: CloudKitRecord, key: string) {
  return value(record, key) === null ? null : number(record, key);
}

function seconds(time: string | null): number | null {
  if (time === null) return null;
  const parsed = clockTime(time);
  return parsed.hour * 3600 + parsed.minute * 60 + parsed.second;
}

function validateAnchors(anchors: unknown[]): asserts anchors is number[] {
  if (anchors.length > 31 || anchors.some(anchor => typeof anchor !== 'number' || !Number.isInteger(anchor) || anchor < 0 || anchor > 30)) {
    throw invalid('Invalid recurrence anchor values.');
  }
}

function periodStart(date: Temporal.PlainDate, unit: Rule['unit']) {
  return unit === 'week' ? date.subtract({ days: date.dayOfWeek - 1 }) : unit === 'month' ? date.with({ day: 1 }) : date;
}

function anchored(period: Temporal.PlainDate, anchor: number, unit: Rule['unit']) {
  return unit === 'week' ? period.add({ days: anchor }) : period.with({ day: Math.min(anchor + 1, period.daysInMonth) });
}

function add(date: Temporal.PlainDate, count: number, unit: Rule['unit']) {
  return date.add({ [unit === 'day' ? 'days' : unit === 'week' ? 'weeks' : unit === 'month' ? 'months' : 'years']: count });
}

function permits(rule: NormalizedRule, date: string) { return rule.repeatUntil === null || date <= rule.repeatUntil; }
function compare(a: Temporal.PlainDate, b: Temporal.PlainDate) { return Temporal.PlainDate.compare(a, b); }
function invalid(message: string) { return new NagareError('INVALID_RECURRENCE', message); }
