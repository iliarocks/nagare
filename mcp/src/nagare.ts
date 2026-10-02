import { Temporal } from '@js-temporal/polyfill';
import { CloudKitError, type CloudKitRecord } from './cloudkit.js';
import {
  NagareError, field, value, text, number, uuid, id, unique, mutable, update, deletion,
  setText, byOrder, validOrder, after, nextOrder, moveOrder, mergeMutations, validateText,
  type Fields, type Mutation, type Store, type Snapshot, type TextScope,
} from './records.js';
import { day, localDate, localTime, scheduleFields, type Schedule } from './calendar.js';
import {
  ruleFromRecord, virtualDates, occurrenceSchedule, createTemplatePlan, editTemplatePlan, advancePlan, stopPlan, type Rule,
} from './recurrence.js';
import { Projects } from './projects.js';

export { NagareError } from './records.js';
export type { Mutation, RecordType, Store as NagareStore } from './records.js';
export type { Schedule } from './calendar.js';

export interface TaskChanges {
  title?: string;
  notes?: string | null;
  schedule?: Schedule;
  projectId?: string | null;
  recurrence?: Rule | null;
}
export interface CreateTask extends TaskChanges { id: string; title: string; schedule: Schedule }
export interface TaskQuery { date?: string; from?: string; through?: string; projectId?: string | null; query?: string }
export interface TaskMove { ids: string[]; revisions: Record<string, string>; beforeId?: string | null; date?: string; projectId?: string }
export interface RecurrenceChanges {
  title?: string; notes?: string | null; rule?: Rule; time?: string | null; endTime?: string | null; projectId?: string | null;
}
export interface TaskInfo {
  id: string; title: string; notes: string | null; date: string;
  time: string | null; endTime: string | null; projectId: string | null;
  virtual: boolean; revision?: string; completedOn?: string;
  recurrence: { id: string; revision?: string; rule: Rule | null; error?: string } | null;
}
type Context = { snapshot: Snapshot; maintenance: Mutation[]; now: number };

/** Uses the app's display and command rules; CloudKit transport stays in the store. */
export class Nagare {
  readonly projects: Projects;

  constructor(private readonly store: Store, private readonly zone: string, private readonly now: () => number = Date.now) {
    Temporal.Now.zonedDateTimeISO(zone);
    this.projects = new Projects(store, now);
  }

  listProjects() { return this.projects.list(); }

  async listTasks(options: TaskQuery = {}): Promise<TaskInfo[]> {
    const projectOnly = options.projectId !== undefined && !options.date && !options.from && !options.through;
    const { snapshot, now } = await this.context('active', !projectOnly);
    const today = localDate(now, this.zone);
    const resolve = (date: string) => date === 'today' ? today : date === 'tomorrow' ? day(today).add({ days: 1 }).toString() : day(date).toString();
    const from = options.date ? resolve(options.date) : options.from ? resolve(options.from) : undefined;
    const through = options.date ? resolve(options.date) : options.through ? resolve(options.through) : undefined;
    if (from && through && from > through) throw new NagareError('INVALID_RANGE', 'The last date must follow the first.');
    const horizon = through ?? day(from && from > today ? from : today).add({ months: 2 }).toString();
    const persisted = snapshot.tasks.filter(record => value(record, 'completedAt') === null);
    const items = persisted.map(record => ({ item: this.task(record, snapshot), record, virtual: false }));

    for (const template of projectOnly ? [] : snapshot.templates) {
      const current = findCurrent(template, snapshot.tasks);
      if (!current) continue;
      const recurrence = this.recurrence(template, true);
      if (!recurrence.rule) continue;
      let dates: string[];
      try {
        dates = virtualDates(localDate(number(current, 'scheduledDate'), this.zone), recurrence.rule, horizon);
      } catch (error) {
        if (!(error instanceof RangeError)) throw error;
        continue;
      }
      for (const date of dates) {
        if (date <= today) continue;
        let occurrence: CloudKitRecord;
        try {
          occurrence = { ...current, fields: occurrenceSchedule(template, date, this.zone) };
        } catch {
          continue;
        }
        const item: TaskInfo = {
          id: 'virtual:' + id(template) + ':' + date,
          title: text(template, 'title') ?? '', notes: text(template, 'notes'), date,
          time: value(occurrence, 'includesTime') === 1 ? localTime(number(occurrence, 'scheduledDate'), this.zone) : null,
          endTime: value(occurrence, 'endDate') === null ? null : localTime(number(occurrence, 'endDate'), this.zone),
          projectId: this.projectId(template, snapshot), virtual: true, recurrence,
        };
        items.push({ item, record: current, virtual: true });
      }
    }
    const project = options.projectId == null ? null : requireRecord(snapshot.projects, options.projectId, 'project');
    return items.filter(({ item }) => (!from || item.date >= from) && (!through || item.date <= through)
      && (options.projectId === undefined || item.projectId === (project ? id(project) : null))
      && matchesText(item, options.query))
      .sort((a, b) => {
        if (projectOnly) return byOrder('projectOrder')(a.record, b.record);
        return a.item.date.localeCompare(b.item.date)
          || Number(a.virtual) - Number(b.virtual)
          || (text(a.record, 'order') ?? '').localeCompare(text(b.record, 'order') ?? '')
          || a.item.id.localeCompare(b.item.id);
      }).map(({ item }) => item);
  }

  async listCompletedTasks(options: Omit<TaskQuery, 'date'> = {}): Promise<TaskInfo[]> {
    const snapshot = await this.snapshot('completed', false);
    if (options.from) day(options.from);
    if (options.through) day(options.through);
    if (options.from && options.through && options.from > options.through) throw new NagareError('INVALID_RANGE', 'The last date must follow the first.');
    const project = options.projectId == null ? null : requireRecord(snapshot.projects, options.projectId, 'project');
    return snapshot.tasks.filter(record => value(record, 'completedAt') !== null)
      .sort((a, b) => number(b, 'completedAt') - number(a, 'completedAt') || byOrder('order')(a, b))
      .map(record => this.task(record, snapshot))
      .filter(item => (!options.from || item.completedOn! >= options.from) && (!options.through || item.completedOn! <= options.through)
        && (options.projectId === undefined || item.projectId === (project ? id(project) : null)) && matchesText(item, options.query));
  }

  async listRecurrences(options: { projectId?: string | null } = {}) {
    const snapshot = await this.snapshot('none');
    const project = options.projectId == null ? null : requireRecord(snapshot.projects, options.projectId, 'project');
    return snapshot.templates.filter(template => options.projectId === undefined || this.projectId(template, snapshot) === (project ? id(project) : null))
      .map(template => this.series(template, snapshot, true));
  }

  async createTask(input: CreateTask): Promise<TaskInfo & { alreadyExists?: boolean }> {
    const taskId = uuid(input.id);
    validateText(input);
    const recordName = 'CD_Todo_' + taskId;
    const existing = await this.store.lookup(recordName);
    const context = await this.context();
    const { snapshot, now } = context;
    const previous = existing ?? snapshot.tasks.find(record => id(record) === taskId);
    if (previous) return { ...this.task(previous, snapshot), alreadyExists: true };
    const operations: Mutation[] = [];
    const project = input.projectId ? requireRecord(snapshot.projects, input.projectId, 'project') : null;
    const task: CloudKitRecord = { recordType: 'CD_Todo', recordName, fields: {
      CD_entityName: field('Todo'), CD_id: field(taskId), CD_syncRecordID: field(crypto.randomUUID().toUpperCase()),
      CD_title: field(input.title), CD_notes: field(input.notes ?? null),
      CD_createdAt: field(now, 'TIMESTAMP'), CD_modifiedAt: field(now, 'TIMESTAMP'),
      ...scheduleFields(input.schedule, this.zone),
      CD_order: field(nextOrder(snapshot.tasks, 'order', operations, now)),
      CD_project: field(project?.recordName ?? null),
      CD_projectOrder: field(project ? nextOrder(projectTasks(snapshot, project.recordName), 'projectOrder', operations, now) : null),
    } };
    if (input.recurrence) {
      const plan = createTemplatePlan(task, input.recurrence, crypto.randomUUID().toUpperCase(), now, this.zone);
      Object.assign(task.fields, plan.taskFields);
      operations.push({ operationType: 'create', record: plan.template });
    }
    operations.push({ operationType: 'create', record: task });
    this.task(task, snapshot);
    try {
      const saved = await this.commit(context, operations);
      return this.task(requireRecord(saved.tasks, taskId, 'task'), saved);
    } catch (error) {
      if (error instanceof CloudKitError && (error.code === 'ALREADY_EXISTS' || error.failures.some(failure => failure.serverErrorCode === 'ALREADY_EXISTS' && failure.recordName === recordName))) {
        const found = await this.store.lookup(recordName);
        if (found) return { ...this.task(found, await this.snapshot()), alreadyExists: true };
      }
      throw error;
    }
  }

  async updateTask(taskId: string, changes: TaskChanges, revision: string): Promise<TaskInfo> {
    validateText(changes);
    const context = await this.context();
    const { snapshot, now } = context;
    const task = requireRecord(snapshot.tasks, taskId, 'task');
    mutable(task, revision);
    const fields: Fields = {};
    const operations: Mutation[] = [];
    if (changes.title !== undefined) setText(fields, 'title', changes.title);
    if (changes.notes !== undefined) setText(fields, 'notes', changes.notes);
    if (changes.schedule) {
      Object.assign(fields, scheduleFields(changes.schedule, this.zone, task));
      if (localDate(number(task, 'scheduledDate'), this.zone) !== changes.schedule.date) {
        fields.CD_order = field(nextOrder(snapshot.tasks.filter(other => other.recordName !== task.recordName
          && value(other, 'completedAt') === null && localDate(number(other, 'scheduledDate'), this.zone) === changes.schedule!.date), 'order', operations, now));
      }
    }
    let template: CloudKitRecord | undefined;
    if (changes.recurrence === null) {
      const link = value(task, 'recurrenceTemplate');
      const candidates = snapshot.templates.filter(item => item.recordName === link || (link === null && findCurrent(item, [task])));
      if (candidates.length > 1) throw new NagareError('SYNC_PENDING', 'More than one recurrence claims this task. Remove the intended recurrence by its own ID.');
      template = candidates[0];
    } else template = this.templateFor(task, snapshot);
    if (changes.projectId !== undefined) {
      this.assign(task, changes.projectId, snapshot, fields, operations, now);
      if (template && value(task, 'completedAt') === null) operations.push(update(template, { CD_project: fields.CD_project, CD_modifiedAt: field(now, 'TIMESTAMP') }));
    }
    if (changes.recurrence === null) {
      if (template) operations.push(...stopPlan(template, snapshot.tasks, now));
      // Also covers a dangling series or a current task awaiting its inverse link.
      if (template || value(task, 'recurrenceTemplate') !== null || value(task, 'recurrenceSequence') !== null) {
        fields.CD_recurrenceTemplate = field(null);
        fields.CD_recurrenceSequence = field(null);
      }
    } else if (changes.recurrence) {
      if (template) operations.push(editTemplatePlan(template, { rule: changes.recurrence }, now, this.zone));
      else {
        const plan = createTemplatePlan({ ...task, fields: { ...task.fields, ...fields } }, changes.recurrence, crypto.randomUUID().toUpperCase(), now, this.zone);
        Object.assign(fields, plan.taskFields);
        operations.push({ operationType: 'create', record: plan.template });
      }
    }
    if (!Object.keys(fields).length && !operations.length) return this.task(task, snapshot);
    if (Object.keys(fields).length) operations.push(update(task, { ...fields, CD_modifiedAt: field(now, 'TIMESTAMP') }));
    const saved = await this.commit(context, operations);
    return this.task(requireRecord(saved.tasks, taskId, 'task'), saved);
  }

  async completeTask(taskId: string, revision: string): Promise<TaskInfo> {
    const context = await this.context();
    const task = requireRecord(context.snapshot.tasks, taskId, 'task');
    mutable(task, revision);
    if (value(task, 'completedAt') !== null) return this.task(task, context.snapshot);
    const template = this.templateFor(task, context.snapshot);
    const operations = template
      ? (await advancePlan(task, template, context.snapshot.tasks, 'complete', context.now, this.zone)).operations
      : [update(task, { CD_completedAt: field(context.now, 'TIMESTAMP'), CD_modifiedAt: field(context.now, 'TIMESTAMP') })];
    const saved = await this.commit(context, operations);
    return this.task(requireRecord(saved.tasks, taskId, 'task'), saved);
  }

  async deleteTask(taskId: string, revision: string) {
    const context = await this.context();
    const task = requireRecord(context.snapshot.tasks, taskId, 'task');
    mutable(task, revision);
    const template = value(task, 'completedAt') === null ? this.templateFor(task, context.snapshot) : undefined;
    const operations = template
      ? (await advancePlan(task, template, context.snapshot.tasks, 'delete', context.now, this.zone)).operations
      : [deletion(task)];
    await this.commit(context, operations);
    return { deleted: id(task) };
  }

  async reinstateTask(taskId: string, revision: string, date?: string): Promise<TaskInfo> {
    const context = await this.context();
    const { snapshot, now } = context;
    const task = requireRecord(snapshot.tasks, taskId, 'task');
    mutable(task, revision);
    if (value(task, 'completedAt') === null) return this.task(task, snapshot);
    const operations: Mutation[] = [];
    const project = value(task, 'project');
    operations.push(update(task, {
      ...scheduleFields({ date: date ?? localDate(now, this.zone) }, this.zone, task),
      CD_completedAt: field(null), CD_recurrenceTemplate: field(null), CD_recurrenceSequence: field(null),
      CD_order: field(nextOrder(snapshot.tasks, 'order', operations, now)),
      CD_projectOrder: field(typeof project === 'string' ? nextOrder(projectTasks(snapshot, project), 'projectOrder', operations, now) : null),
      CD_modifiedAt: field(now, 'TIMESTAMP'),
    }));
    const saved = await this.commit(context, operations);
    return this.task(requireRecord(saved.tasks, taskId, 'task'), saved);
  }

  async reorderTasks(input: TaskMove): Promise<TaskInfo[]> {
    if ((input.date === undefined) === (input.projectId === undefined)) throw new NagareError('INVALID_MOVE', 'Choose a date list or a project list.');
    const context = await this.context();
    const { snapshot, now } = context;
    const revisions = new Map(Object.entries(input.revisions).map(([taskId, revision]) => [uuid(taskId), revision]));
    const selected = input.ids.map(taskId => {
      const task = requireRecord(snapshot.tasks, taskId, 'task');
      const revision = revisions.get(id(task));
      if (!revision) throw new NagareError('CONFLICT', 'Read each selected task before moving it.');
      mutable(task, revision);
      if (value(task, 'completedAt') !== null) throw new NagareError('INVALID_MOVE', 'Reinstate completed tasks before moving them.');
      return task;
    });
    const operations: Mutation[] = [];
    let destination: CloudKitRecord[];
    let key: string;
    if (input.projectId !== undefined) {
      const project = requireRecord(snapshot.projects, input.projectId, 'project');
      destination = projectTasks(snapshot, project.recordName);
      key = 'projectOrder';
      for (const task of selected) {
        const template = this.templateFor(task, snapshot);
        operations.push(update(task, { CD_project: field(project.recordName), CD_modifiedAt: field(now, 'TIMESTAMP') }));
        if (template) operations.push(update(template, { CD_project: field(project.recordName), CD_modifiedAt: field(now, 'TIMESTAMP') }));
      }
    } else {
      const date = day(input.date!).toString();
      destination = snapshot.tasks.filter(task => value(task, 'completedAt') === null && localDate(number(task, 'scheduledDate'), this.zone) === date);
      key = 'order';
      for (const task of selected) operations.push(update(task, { ...scheduleFields({ date }, this.zone, task), CD_modifiedAt: field(now, 'TIMESTAMP') }));
    }
    operations.push(...moveOrder(destination, selected, input.beforeId ?? null, key, now));
    const saved = await this.commit(context, operations);
    const moved = selected.map(task => this.task(requireRecord(saved.tasks, id(task), 'task'), saved));
    return moved;
  }

  async updateRecurrence(seriesId: string, changes: RecurrenceChanges, revision: string) {
    validateText(changes);
    const context = await this.context();
    const { snapshot, now } = context;
    const template = requireRecord(snapshot.templates, seriesId, 'recurrence');
    mutable(template, revision);
    const fields: Fields = {};
    const operations: Mutation[] = [];
    if (changes.title !== undefined) setText(fields, 'title', changes.title);
    if (changes.notes !== undefined) setText(fields, 'notes', changes.notes);
    if (changes.rule !== undefined || changes.time !== undefined || changes.endTime !== undefined) {
      operations.push(editTemplatePlan(template, changes, now, this.zone));
    }
    if (changes.projectId !== undefined) {
      const current = this.current(template, snapshot);
      const taskFields: Fields = {};
      this.assign(current, changes.projectId, snapshot, taskFields, operations, now);
      fields.CD_project = taskFields.CD_project;
      operations.push(update(current, { ...taskFields, CD_modifiedAt: field(now, 'TIMESTAMP') }));
    }
    if (Object.keys(fields).length) operations.push(update(template, { ...fields, CD_modifiedAt: field(now, 'TIMESTAMP') }));
    if (!operations.length) return this.series(template, snapshot);
    const saved = await this.commit(context, operations);
    return this.series(requireRecord(saved.templates, seriesId, 'recurrence'), saved);
  }

  async stopRecurrence(seriesId: string, revision: string) {
    const context = await this.context();
    const template = requireRecord(context.snapshot.templates, seriesId, 'recurrence');
    mutable(template, revision);
    const current = this.current(template, context.snapshot);
    const saved = await this.commit(context, stopPlan(template, context.snapshot.tasks, context.now));
    return this.task(requireRecord(saved.tasks, id(current), 'task'), saved);
  }

  private async snapshot(taskText: TextScope = 'all', templateText = true): Promise<Snapshot> {
    const [tasks, projects, templates] = await Promise.all([
      this.store.list('CD_Todo', taskText).then(unique),
      this.store.list('CD_Project', 'none').then(unique),
      this.store.list('CD_RecurrenceTemplate', templateText ? 'all' : 'none').then(unique),
    ]);
    return { tasks, projects, templates };
  }

  /** Reads project native day maintenance without changing CloudKit. */
  private async context(taskText: TextScope = 'all', templateText = true): Promise<Context> {
    const snapshot = await this.snapshot(taskText, templateText);
    const now = this.now();
    const today = localDate(now, this.zone);
    const maintenance: Mutation[] = [];
    let order = nextOrder(snapshot.tasks, 'order', maintenance, now);
    const overdue = snapshot.tasks.filter(task => value(task, 'completedAt') === null && localDate(number(task, 'scheduledDate'), this.zone) < today)
      .sort((a, b) => number(a, 'scheduledDate') - number(b, 'scheduledDate') || (text(a, 'order') ?? '').localeCompare(text(b, 'order') ?? '')
        || number(a, 'createdAt') - number(b, 'createdAt') || id(a).localeCompare(id(b)));
    for (const task of overdue) {
      maintenance.push(update(task, { ...scheduleFields({ date: today }, this.zone, task), CD_order: field(order), CD_modifiedAt: field(now, 'TIMESTAMP') }));
      order = after(order);
    }
    return { snapshot: apply(snapshot, mergeMutations(maintenance)), maintenance, now };
  }

  private async commit(context: Context, operations: Mutation[]): Promise<Snapshot> {
    const command = mergeMutations(operations);
    if (command.length > 200) throw new NagareError('TRANSACTION_TOO_LARGE', 'This change affects more than 200 records. Split it into smaller changes.');
    const merged = mergeMutations([...context.maintenance, ...command]);
    const planned = apply(context.snapshot, merged);
    for (const operation of merged) {
      if (operation.operationType === 'delete') continue;
      const task = planned.tasks.find(record => record.recordName === operation.record.recordName);
      if (task) {
        this.task(task, planned);
        if (value(task, 'recurrenceTemplate') !== null && value(task, 'endDate') !== null
          && localDate(number(task, 'scheduledDate'), this.zone) !== localDate(number(task, 'endDate'), this.zone)) {
          throw new NagareError('INVALID_SCHEDULE', 'Repeating tasks must start and end on the same day.');
        }
      }
      const template = planned.templates.find(record => record.recordName === operation.record.recordName);
      if (template) this.series(template, planned);
    }
    if (merged.length <= 200) return apply(context.snapshot, merged, await this.store.modify(merged));

    // Keep the requested command atomic. Large day maintenance runs first in
    // append order, so an interruption cannot move a middle overdue task ahead.
    let snapshot = context.snapshot;
    const maintenance = mergeMutations(context.maintenance).sort((a, b) =>
      (text(a.record, 'order') ?? '').localeCompare(text(b.record, 'order') ?? ''));
    for (let index = 0; index < maintenance.length; index += 200) {
      const batch = maintenance.slice(index, index + 200);
      snapshot = apply(snapshot, batch, await this.store.modify(batch));
    }
    const acknowledged = new Map([...snapshot.tasks, ...snapshot.projects, ...snapshot.templates].map(record => [record.recordName, record]));
    const rebased = command.map(operation => operation.operationType === 'create' ? operation : {
      ...operation, record: { ...operation.record, recordChangeTag: acknowledged.get(operation.record.recordName)?.recordChangeTag },
    });
    return apply(snapshot, rebased, await this.store.modify(rebased));
  }

  private task(record: CloudKitRecord, snapshot: Snapshot): TaskInfo {
    const start = number(record, 'scheduledDate');
    const template = snapshot.templates.find(item => item.recordName === value(record, 'recurrenceTemplate'));
    return {
      id: id(record), title: text(record, 'title') ?? '', notes: text(record, 'notes'),
      date: localDate(start, this.zone), time: value(record, 'includesTime') === 1 ? localTime(start, this.zone) : null,
      endTime: value(record, 'endDate') === null ? null : localTime(number(record, 'endDate'), this.zone),
      projectId: this.projectId(record, snapshot), virtual: false,
      revision: record.recordChangeTag, recurrence: template ? this.recurrence(template, true) : null,
      ...(value(record, 'completedAt') === null ? {} : { completedOn: localDate(number(record, 'completedAt'), this.zone) }),
    };
  }

  private recurrence(template: CloudKitRecord, tolerateInvalid = false) {
    const identity = { id: id(template), revision: template.recordChangeTag };
    try {
      return { ...identity, rule: ruleFromRecord(template, this.zone) };
    } catch {
      const message = 'The stored repeat rule is invalid. Replace its rule with update_recurrence or remove the recurrence.';
      if (!tolerateInvalid) throw new NagareError('INVALID_RECURRENCE', message);
      return { ...identity, rule: null, error: message };
    }
  }

  private series(template: CloudKitRecord, snapshot: Snapshot, tolerateInvalid = false) {
    return {
      ...this.recurrence(template, tolerateInvalid), title: text(template, 'title') ?? '', notes: text(template, 'notes'),
      time: timeFromSeconds(value(template, 'startTimeSeconds')), endTime: timeFromSeconds(value(template, 'endTimeSeconds')),
      projectId: this.projectId(template, snapshot), currentTaskId: text(template, 'currentItemID'),
    };
  }

  private projectId(record: CloudKitRecord, snapshot: Snapshot): string | null {
    const project = snapshot.projects.find(item => item.recordName === value(record, 'project'));
    return project ? id(project) : null;
  }

  private templateFor(task: CloudKitRecord, snapshot: Snapshot): CloudKitRecord | undefined {
    const link = value(task, 'recurrenceTemplate');
    if (link === null && value(task, 'recurrenceSequence') === null) return;
    const template = snapshot.templates.find(item => item.recordName === link);
    if (!template) throw new NagareError('SYNC_PENDING', 'The repeating task is still syncing its recurrence rule. Try again shortly.');
    return template;
  }

  private current(template: CloudKitRecord, snapshot: Snapshot): CloudKitRecord {
    const current = findCurrent(template, snapshot.tasks);
    if (!current) throw new NagareError('SYNC_PENDING', 'A repeating task is still syncing its current occurrence. Try again shortly.');
    return current;
  }

  private assign(task: CloudKitRecord, projectId: string | null, snapshot: Snapshot, fields: Fields, operations: Mutation[], now: number): void {
    const project = projectId ? requireRecord(snapshot.projects, projectId, 'project') : null;
    fields.CD_project = field(project?.recordName ?? null);
    if (!project) fields.CD_projectOrder = field(null);
    else if (value(task, 'project') !== project.recordName || !validOrder(text(task, 'projectOrder'))) {
      fields.CD_projectOrder = field(nextOrder(projectTasks(snapshot, project.recordName).filter(other => other.recordName !== task.recordName), 'projectOrder', operations, now));
    } else fields.CD_projectOrder = field(value(task, 'projectOrder'));
  }
}

function requireRecord(records: CloudKitRecord[], recordId: string, kind: string): CloudKitRecord {
  const record = records.find(item => id(item) === uuid(recordId));
  if (!record) throw new NagareError('NOT_FOUND', 'This ' + kind + ' no longer exists.');
  return record;
}
function projectTasks(snapshot: Snapshot, recordName: string) {
  return snapshot.tasks.filter(task => value(task, 'project') === recordName && value(task, 'completedAt') === null);
}
function matchesText(item: { title: string; notes: string | null }, query?: string): boolean {
  return !query || (item.title + '\n' + (item.notes ?? '')).toLocaleLowerCase().includes(query.toLocaleLowerCase());
}
function timeFromSeconds(value: unknown): string | null {
  if (value === null) return null;
  if (typeof value !== 'number' || !Number.isInteger(value) || value < 0 || value >= 86400) throw new NagareError('INVALID_RECORD', 'Invalid repeating time.');
  return String(Math.floor(value / 3600)).padStart(2, '0') + ':' + String(Math.floor(value % 3600 / 60)).padStart(2, '0');
}
function apply(snapshot: Snapshot, operations: Mutation[], saved: CloudKitRecord[] = []): Snapshot {
  const records = new Map([...snapshot.tasks, ...snapshot.projects, ...snapshot.templates].map(record => [record.recordName, record]));
  for (const operation of operations) {
    const record = operation.record;
    if (operation.operationType === 'delete') records.delete(record.recordName);
    else {
      const original = records.get(record.recordName);
      const response = saved.find(item => item.recordName === record.recordName);
      records.set(record.recordName, { ...record, ...response, fields: { ...original?.fields, ...record.fields, ...response?.fields } });
    }
  }
  const all = [...records.values()];
  return {
    tasks: all.filter(record => record.recordType === 'CD_Todo'), projects: all.filter(record => record.recordType === 'CD_Project'),
    templates: all.filter(record => record.recordType === 'CD_RecurrenceTemplate'),
  };
}

function findCurrent(template: CloudKitRecord, tasks: CloudKitRecord[]) {
  return tasks.find(task => id(task) === text(template, 'currentItemID')?.toUpperCase()
    && value(task, 'recurrenceSequence') === value(template, 'currentSequence')
    && (value(task, 'recurrenceTemplate') === null || value(task, 'recurrenceTemplate') === template.recordName)
    && value(task, 'completedAt') === null);
}
