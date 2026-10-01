import { Temporal } from '@js-temporal/polyfill';
import { CloudKitError } from './cloudkit.js';
import type { CloudKitRecord } from './cloudkit.js';

export type RecordType = 'CD_Todo' | 'CD_Project';
export type Mutation = { operationType: 'create' | 'update'; record: CloudKitRecord };

// The adapter supplies every page and applies a batch atomically in one zone.
export interface NagareStore {
  list(recordType: RecordType): Promise<CloudKitRecord[]>;
  lookup(recordName: string): Promise<CloudKitRecord | undefined>;
  modify(operations: Mutation[]): Promise<CloudKitRecord[]>;
}

export interface Schedule {
  date: string;
  time?: string | null;
  endTime?: string | null;
}

export interface TaskChanges {
  title?: string;
  notes?: string | null;
  schedule?: Schedule;
  projectId?: string | null;
}

export interface CreateTask extends TaskChanges {
  id: string;
  title: string;
  schedule: Schedule;
}

export class NagareError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message);
    this.name = 'NagareError';
  }
}

type Snapshot = { tasks: CloudKitRecord[]; projects: CloudKitRecord[] };
type Fields = CloudKitRecord['fields'];

export class Nagare {
  constructor(
    private readonly store: NagareStore,
    private readonly timeZone: string,
    private readonly now: () => number = Date.now,
  ) {
    Temporal.Now.zonedDateTimeISO(timeZone);
  }

  async listProjects() {
    return unique(await this.store.list('CD_Project')).sort(byOrder('order')).map(project => ({
      id: id(project),
      title: text(project, 'title') ?? '',
      notes: text(project, 'notes'),
      prioritized: value(project, 'priorityRawValue') == null
        ? value(project, 'isPriority') === 1
        : value(project, 'priorityRawValue') === 2,
    }));
  }

  async listTasks(options: { completed?: boolean; projectId?: string; date?: string } = {}) {
    const snapshot = await this.snapshot();
    if (options.date) day(options.date);
    const project = options.projectId ? requireProject(snapshot, options.projectId) : null;
    return snapshot.tasks
      .filter(record => options.completed === undefined || (value(record, 'completedAt') != null) === options.completed)
      .filter(record => !project || value(record, 'project') === project.recordName)
      .filter(record => !options.date || this.localDate(requiredNumber(record, 'scheduledDate')) === options.date)
      .sort(byOrder(project ? 'projectOrder' : 'order'))
      .map(record => this.task(record, snapshot));
  }

  async createTask(input: CreateTask) {
    const taskId = uuid(input.id);
    validateChanges(input);
    const recordName = `CD_Todo_${taskId}`;
    const previouslyCreated = await this.store.lookup(recordName);
    const snapshot = await this.snapshot();
    const existing = previouslyCreated ?? snapshot.tasks.find(record => id(record) === taskId);
    if (existing) {
      // A retry never overwrites the task, including edits made since creation.
      return { ...this.task(existing, snapshot), alreadyExists: true };
    }
    const timestamp = this.now();
    const project = input.projectId ? requireProject(snapshot, input.projectId) : null;
    const schedule = this.schedule(input.schedule);
    const repairs: Mutation[] = [];
    const fields: Fields = {
      CD_entityName: field('Todo'),
      CD_id: field(taskId),
      CD_syncRecordID: field(crypto.randomUUID().toUpperCase()),
      CD_title: field(input.title),
      CD_notes: field(input.notes ?? null),
      CD_createdAt: field(timestamp, 'TIMESTAMP'),
      CD_modifiedAt: field(timestamp, 'TIMESTAMP'),
      ...schedule,
      CD_order: field(this.nextOrder(snapshot.tasks, 'order', repairs, timestamp)),
      CD_project: field(project?.recordName ?? null),
      CD_projectOrder: field(project
        ? this.nextOrder(activeProjectTasks(snapshot, project.recordName), 'projectOrder', repairs, timestamp)
        : null),
    };
    const record: CloudKitRecord = { recordType: 'CD_Todo', recordName, fields };
    this.task(record, snapshot);
    let saved: CloudKitRecord[];
    try {
      saved = await this.store.modify([...mergeRepairs(repairs), { operationType: 'create', record }]);
    } catch (error) {
      if (error instanceof CloudKitError && (error.code === 'ALREADY_EXISTS'
        || error.failures.some(failure => failure.serverErrorCode === 'ALREADY_EXISTS' && failure.recordName === recordName))) {
        const existing = await this.store.lookup(recordName);
        if (existing) return { ...this.task(existing, snapshot), alreadyExists: true };
      }
      throw error;
    }
    return this.task(saved.find(item => item.recordName === record.recordName) ?? record, snapshot);
  }

  async updateTask(taskId: string, changes: TaskChanges, expectedRevision?: string) {
    validateChanges(changes);
    const snapshot = await this.snapshot();
    const record = requireTask(snapshot, taskId);
    mutable(record, expectedRevision);
    const timestamp = this.now();
    const fields: Fields = {};
    const repairs: Mutation[] = [];
    if (changes.title !== undefined) setText(fields, 'title', changes.title);
    if (changes.notes !== undefined) setText(fields, 'notes', changes.notes);
    if (changes.schedule) {
      Object.assign(fields, this.schedule(changes.schedule, record));
      if (this.localDate(requiredNumber(record, 'scheduledDate')) !== changes.schedule.date) {
        const destination = snapshot.tasks.filter(item => item.recordName !== record.recordName
          && value(item, 'completedAt') == null
          && this.localDate(requiredNumber(item, 'scheduledDate')) === changes.schedule!.date);
        fields.CD_order = field(this.nextOrder(destination, 'order', repairs, timestamp));
      }
    }
    if (changes.projectId !== undefined) {
      const project = changes.projectId === null ? null : requireProject(snapshot, changes.projectId);
      fields.CD_project = field(project?.recordName ?? null);
      if (!project) fields.CD_projectOrder = field(null);
      else if (value(record, 'project') !== project.recordName || !validOrder(text(record, 'projectOrder'))) {
        fields.CD_projectOrder = field(this.nextOrder(
          activeProjectTasks(snapshot, project.recordName).filter(item => item.recordName !== record.recordName),
          'projectOrder', repairs, timestamp,
        ));
      }
    }
    if (!Object.keys(fields).length) return this.task(record, snapshot);
    fields.CD_modifiedAt = field(timestamp, 'TIMESTAMP');
    // A response-format error must not follow a successful write. In particular,
    // untouched asset-backed text is not yet supported by this prototype.
    const result = { ...record, fields: { ...record.fields, ...fields } };
    this.task(result, snapshot);
    const saved = await this.store.modify([...mergeRepairs(repairs), update(record, fields)]);
    return this.task(saved.find(item => item.recordName === record.recordName)
      ?? result, snapshot);
  }

  async completeTask(taskId: string, expectedRevision?: string) {
    const snapshot = await this.snapshot();
    const record = requireTask(snapshot, taskId);
    mutable(record, expectedRevision);
    this.task(record, snapshot);
    if (value(record, 'completedAt') != null) return this.task(record, snapshot);
    const timestamp = this.now();
    const fields = { CD_completedAt: field(timestamp, 'TIMESTAMP'), CD_modifiedAt: field(timestamp, 'TIMESTAMP') };
    const saved = await this.store.modify([update(record, fields)]);
    return this.task(saved[0] ?? { ...record, fields: { ...record.fields, ...fields } }, snapshot);
  }

  private async snapshot(): Promise<Snapshot> {
    return {
      tasks: unique(await this.store.list('CD_Todo')),
      projects: unique(await this.store.list('CD_Project')),
    };
  }

  private task(record: CloudKitRecord, snapshot: Snapshot) {
    const start = requiredNumber(record, 'scheduledDate');
    const project = snapshot.projects.find(item => item.recordName === value(record, 'project'));
    return {
      id: id(record),
      title: text(record, 'title') ?? '',
      notes: text(record, 'notes'),
      date: this.localDate(start),
      time: value(record, 'includesTime') === 1 ? this.localTime(start) : null,
      scheduledAt: new Date(start).toISOString(),
      endAt: isoDate(record, 'endDate'),
      timeZone: this.timeZone,
      completedAt: isoDate(record, 'completedAt'),
      projectId: project ? id(project) : null,
      recurring: recurring(record),
      revision: record.recordChangeTag,
    };
  }

  private localDate(timestamp: number) {
    return Temporal.Instant.fromEpochMilliseconds(timestamp).toZonedDateTimeISO(this.timeZone).toPlainDate().toString();
  }

  private localTime(timestamp: number) {
    return Temporal.Instant.fromEpochMilliseconds(timestamp).toZonedDateTimeISO(this.timeZone).toPlainTime().toString();
  }

  private schedule(input: Schedule, existing?: CloudKitRecord): Fields {
    const date = day(input.date);
    if (input.time === '' || input.endTime === '') throw new NagareError('INVALID_SCHEDULE', 'Use null to remove a time.');
    const oldStart = existing ? requiredNumber(existing, 'scheduledDate') : null;
    const time = input.time === undefined
      ? existing && value(existing, 'includesTime') === 1 ? this.localTime(oldStart!) : null
      : input.time;
    const start = time ? calendarTime(date, clockTime(time), this.timeZone) : date.toZonedDateTime(this.timeZone).epochMilliseconds;
    let end: number | null = null;
    if (time && input.endTime) end = calendarTime(date, clockTime(input.endTime), this.timeZone);
    else if (!time && input.endTime) throw new NagareError('INVALID_SCHEDULE', 'An end time requires a start time.');
    else if (time && input.endTime === undefined && existing && value(existing, 'endDate') != null) {
      end = start + requiredNumber(existing, 'endDate') - oldStart!;
    }
    if (end !== null && end <= start) throw new NagareError('INVALID_SCHEDULE', 'The end time must follow the start time.');
    return {
      CD_scheduledDate: field(start, 'TIMESTAMP'),
      CD_includesTime: field(time ? 1 : 0, 'INT64'),
      CD_endDate: field(end, 'TIMESTAMP'),
    };
  }

  private nextOrder(records: CloudKitRecord[], key: 'order' | 'projectOrder', repairs: Mutation[], timestamp: number) {
    const sorted = [...records].sort(byOrder(key));
    if (sorted.every(record => validOrder(text(record, key)))) return after(text(sorted.at(-1), key));
    const maximum = 36n ** 12n - 1n;
    const step = maximum / BigInt(sorted.length + 1);
    sorted.forEach((record, index) => {
      // Repairing a recurring item is itself a recurring mutation; leave it to Nagare.
      mutable(record);
      repairs.push(update(record, {
        [`CD_${key}`]: field((step * BigInt(index + 1)).toString(36).padStart(12, '0')),
        CD_modifiedAt: field(timestamp, 'TIMESTAMP'),
      }));
    });
    return after(sorted.length ? (step * BigInt(sorted.length)).toString(36).padStart(12, '0') : null);
  }
}

function field(value: string | number | null, type?: string): Fields[string] {
  return type ? { value, type } : { value };
}

function value(record: CloudKitRecord | undefined, key: string) {
  return record?.fields[`CD_${key}`]?.value ?? null;
}

function text(record: CloudKitRecord | undefined, key: string): string | null {
  const result = value(record, key);
  if ((result === null || result === '') && value(record, `${key}_ckAsset`) != null) {
    throw new NagareError('EXTERNAL_TEXT', `This ${key} is stored as an asset and cannot yet be read by this prototype.`);
  }
  if (result !== null && typeof result !== 'string') throw new NagareError('INVALID_RECORD', `Unexpected ${key} field type.`);
  return result;
}

function requiredNumber(record: CloudKitRecord, key: string): number {
  const result = value(record, key);
  if (typeof result !== 'number' || !Number.isFinite(result)) throw new NagareError('INVALID_RECORD', `Missing or invalid ${key}.`);
  return result;
}

function isoDate(record: CloudKitRecord, key: string) {
  return value(record, key) == null ? null : new Date(requiredNumber(record, key)).toISOString();
}

function uuid(value: string) {
  if (!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value)) {
    throw new NagareError('INVALID_ID', 'Use a UUID for the task or project ID.');
  }
  return value.toUpperCase();
}

function id(record: CloudKitRecord) { return uuid(text(record, 'id') ?? ''); }

function unique(records: CloudKitRecord[]) {
  const ids = new Set<string>();
  for (const record of records) {
    const key = id(record);
    if (ids.has(key)) throw new NagareError('SYNC_PENDING', 'Nagare has duplicate records awaiting sync reconciliation. Open the app before editing them here.');
    ids.add(key);
  }
  return records;
}

function requireTask(snapshot: Snapshot, taskId: string) {
  const record = snapshot.tasks.find(item => id(item) === uuid(taskId));
  if (!record) throw new NagareError('NOT_FOUND', 'This task no longer exists.');
  return record;
}

function requireProject(snapshot: Snapshot, projectId: string) {
  const record = snapshot.projects.find(item => id(item) === uuid(projectId));
  if (!record) throw new NagareError('NOT_FOUND', 'This project no longer exists.');
  return record;
}

function recurring(record: CloudKitRecord) {
  return value(record, 'recurrenceTemplate') != null || value(record, 'recurrenceSequence') != null;
}

function mutable(record: CloudKitRecord, expectedRevision?: string) {
  if (recurring(record)) throw new NagareError('RECURRING_TASK', 'Recurring tasks can be read here. Edit or complete them in Nagare for now.');
  if (!record.recordChangeTag || (expectedRevision !== undefined && record.recordChangeTag !== expectedRevision)) {
    throw new NagareError('CONFLICT', 'The task changed. Read it again before applying this edit.');
  }
}

function update(record: CloudKitRecord, fields: Fields): Mutation {
  if (!record.recordChangeTag) throw new NagareError('CONFLICT', 'The record has no revision for a safe update.');
  return { operationType: 'update', record: {
    recordName: record.recordName, recordType: record.recordType, recordChangeTag: record.recordChangeTag, fields,
  } };
}

function setText(fields: Fields, key: string, value: string | null) {
  fields[`CD_${key}`] = field(value);
  fields[`CD_${key}_ckAsset`] = field(null);
}

function validateChanges(changes: TaskChanges) {
  if (changes.title !== undefined && (!changes.title.trim() || changes.title.length > 10_000)) {
    throw new NagareError('INVALID_TITLE', 'Use a nonempty title of at most 10,000 characters.');
  }
  if (changes.notes && new TextEncoder().encode(changes.notes).length > 500_000) {
    throw new NagareError('NOTES_TOO_LONG', 'Notes must fit within 500 KB for this prototype.');
  }
}

function day(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new NagareError('INVALID_SCHEDULE', 'Use a date in YYYY-MM-DD form.');
  return Temporal.PlainDate.from(value, { overflow: 'reject' });
}

function clockTime(value: string) {
  if (!/^\d{2}:\d{2}(?::\d{2}(?:\.\d{1,3})?)?$/.test(value)) throw new NagareError('INVALID_SCHEDULE', 'Use a time in HH:mm or HH:mm:ss form.');
  return Temporal.PlainTime.from(value, { overflow: 'reject' });
}

// Calendar.date(bySettingHour:) picks the first occurrence of repeated time,
// and the next valid instant when a daylight-saving transition skips that time.
function calendarTime(date: Temporal.PlainDate, time: Temporal.PlainTime, zone: string): number {
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

function activeProjectTasks(snapshot: Snapshot, projectRecordName: string) {
  return snapshot.tasks.filter(item => value(item, 'project') === projectRecordName && value(item, 'completedAt') == null);
}

function byOrder(key: string) {
  return (a: CloudKitRecord, b: CloudKitRecord) => {
    const left = text(a, key) ?? (key === 'order' ? '' : null);
    const right = text(b, key) ?? (key === 'order' ? '' : null);
    if (left !== right) return left === null ? 1 : right === null ? -1 : left < right ? -1 : 1;
    return id(a) === id(b) ? 0 : id(a) < id(b) ? -1 : 1;
  };
}

function validOrder(order: string | null): order is string { return order !== null && /^[0-9a-z]+$/.test(order); }

// The append case of Nagare's FractionalIndex.between(previous, nil).
function after(previous: string | null): string {
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  let prefix = '';
  for (const digit of previous ?? '') {
    const index = digits.indexOf(digit);
    if (index + 1 < digits.length) return prefix + digits[Math.floor((index + digits.length) / 2)];
    prefix += digit;
  }
  return prefix + 'i';
}

function mergeRepairs(repairs: Mutation[]) {
  const merged = new Map<string, Mutation>();
  for (const repair of repairs) {
    const existing = merged.get(repair.record.recordName);
    if (existing) Object.assign(existing.record.fields, repair.record.fields);
    else merged.set(repair.record.recordName, repair);
  }
  return [...merged.values()];
}
