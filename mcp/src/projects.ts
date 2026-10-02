import { CloudKitError, type CloudKitRecord } from './cloudkit.js';
import {
  NagareError, byOrder, deletion, field, id, mergeMutations, moveOrder, mutable,
  nextOrder, setText, text, unique, update, uuid, validateText, value,
  type Fields, type Mutation, type Store,
} from './records.js';

export interface ProjectChanges {
  title?: string;
  notes?: string | null;
  prioritized?: boolean;
}

export interface CreateProject extends ProjectChanges { id: string; title: string }

export interface ProjectMove {
  ids: string[];
  beforeId?: string | null;
  prioritized?: boolean;
  revisions: Record<string, string>;
}

export class Projects {
  constructor(private readonly store: Store, private readonly now: () => number = Date.now) {}

  async list() {
    return ordered(await this.records()).map(project);
  }

  async create(input: CreateProject) {
    const projectId = uuid(input.id);
    validateText(input);
    const recordName = `CD_Project_${projectId}`;
    const previous = await this.store.lookup(recordName);
    const projects = await this.records();
    const existing = previous ?? projects.find(record => id(record) === projectId);
    if (existing) return { ...project(existing), alreadyExists: true };

    const timestamp = this.now();
    const prioritized = input.prioritized ?? false;
    const repairs: Mutation[] = [];
    const record: CloudKitRecord = {
      recordType: 'CD_Project', recordName,
      fields: {
        CD_entityName: field('Project'), CD_id: field(projectId),
        CD_syncRecordID: field(crypto.randomUUID().toUpperCase()),
        CD_title: field(input.title), CD_notes: field(input.notes ?? null),
        CD_createdAt: field(timestamp, 'TIMESTAMP'), CD_modifiedAt: field(timestamp, 'TIMESTAMP'),
        ...priorityFields(prioritized),
        CD_order: field(nextOrder(projects.filter(item => isPriority(item) === prioritized), 'order', repairs, timestamp)),
      },
    };
    try {
      const saved = await this.store.modify([...repairs, { operationType: 'create', record }]);
      return project(saved.find(item => item.recordName === recordName) ?? record);
    } catch (error) {
      if (error instanceof CloudKitError && (error.code === 'ALREADY_EXISTS'
        || error.failures.some(failure => failure.serverErrorCode === 'ALREADY_EXISTS' && failure.recordName === recordName))) {
        const existing = await this.store.lookup(recordName);
        if (existing) return { ...project(existing), alreadyExists: true };
      }
      throw error;
    }
  }

  async update(projectId: string, changes: ProjectChanges, revision: string) {
    validateText(changes);
    const projects = await this.records();
    const record = requireProject(projects, projectId);
    mutable(record, revision);
    const timestamp = this.now();
    const fields: Fields = {};
    const mutations: Mutation[] = [];
    if (changes.title !== undefined) setText(fields, 'title', changes.title);
    if (changes.notes !== undefined) setText(fields, 'notes', changes.notes);
    if (changes.prioritized !== undefined) {
      Object.assign(fields, priorityFields(changes.prioritized));
      if (changes.prioritized !== isPriority(record)) {
        const destination = projects.filter(item => isPriority(item) === changes.prioritized).sort(byOrder('order'));
        // Match the native swipe: promotion goes last; demotion goes first.
        const beforeId = changes.prioritized || !destination.length ? null : id(destination[0]);
        mutations.push(...moveOrder(destination, [record], beforeId, 'order', timestamp));
      }
    }
    if (!Object.keys(fields).length) return project(record);
    fields.CD_modifiedAt = field(timestamp, 'TIMESTAMP');
    const batch = mergeMutations([...mutations, update(record, fields)]);
    const patched = patch(record, batch);
    project(patched);
    const saved = await this.store.modify(batch);
    return project(mergeSaved(patched, saved));
  }

  async delete(projectId: string, revision: string) {
    const record = requireProject(await this.records(), projectId);
    mutable(record, revision);
    const tasks = await this.store.list('CD_Todo', 'none');
    const templates = await this.store.list('CD_RecurrenceTemplate', 'none');
    const timestamp = this.now();
    const detach = [...tasks, ...templates]
      .filter(item => value(item, 'project') === record.recordName)
      .map(item => update(item, {
        CD_project: field(null), CD_modifiedAt: field(timestamp, 'TIMESTAMP'),
        ...(item.recordType === 'CD_Todo' ? { CD_projectOrder: field(null) } : {}),
      }));
    await this.store.modify([...detach, deletion(record)]);
    return { id: id(record), deleted: true };
  }

  async reorder(input: ProjectMove) {
    const projects = await this.records();
    const selected = input.ids.map(projectId => requireProject(projects, projectId));
    if (!selected.length || new Set(selected.map(id)).size !== selected.length) {
      throw new NagareError('INVALID_MOVE', 'Select each project once.');
    }
    const revisions = new Map(Object.entries(input.revisions).map(([projectId, revision]) => [uuid(projectId), revision]));
    for (const record of selected) {
      const revision = revisions.get(id(record));
      if (!revision) throw new NagareError('CONFLICT', 'Read each selected project before moving it.');
      mutable(record, revision);
    }
    const before = input.beforeId ? requireProject(projects, input.beforeId) : undefined;
    const prioritized = input.prioritized ?? (before ? isPriority(before) : isPriority(selected[0]));
    if ((before && isPriority(before) !== prioritized)
      || (input.prioritized === undefined && !before && selected.some(record => isPriority(record) !== prioritized))) {
      throw new NagareError('INVALID_MOVE', 'Choose one priority group for the destination.');
    }
    const destination = projects.filter(record => isPriority(record) === prioritized);
    for (const record of destination) {
      const revision = revisions.get(id(record));
      if (revision !== undefined) mutable(record, revision);
    }
    const timestamp = this.now();
    const mutations = mergeMutations([
      ...moveOrder(destination, selected, before ? id(before) : null, 'order', timestamp),
      ...selected.filter(record => isPriority(record) !== prioritized).map(record => update(record, {
        ...priorityFields(prioritized), CD_modifiedAt: field(timestamp, 'TIMESTAMP'),
      })),
    ]);
    const saved = mutations.length ? await this.store.modify(mutations) : [];
    const result = projects.map(record => mergeSaved(patch(record, mutations), saved));
    return ordered(result).map(project);
  }

  private async records() { return unique(await this.store.list('CD_Project')); }
}

function isPriority(record: CloudKitRecord): boolean {
  const raw = value(record, 'priorityRawValue');
  if (raw === 0 || raw === 1) return false;
  if (raw === 2) return true;
  return value(record, 'isPriority') === 1 || value(record, 'isPriority') === true;
}

function priorityFields(prioritized: boolean): Fields {
  return { CD_isPriority: field(prioritized ? 1 : 0, 'INT64'), CD_priorityRawValue: field(prioritized ? 2 : 1, 'INT64') };
}

function ordered(projects: CloudKitRecord[]) {
  return [...projects].sort((left, right) => Number(isPriority(right)) - Number(isPriority(left)) || byOrder('order')(left, right));
}

function requireProject(projects: CloudKitRecord[], projectId: string) {
  const record = projects.find(item => id(item) === uuid(projectId));
  if (!record) throw new NagareError('NOT_FOUND', 'This project no longer exists.');
  return record;
}

function project(record: CloudKitRecord) {
  return {
    id: id(record), title: text(record, 'title') ?? '', notes: text(record, 'notes'),
    prioritized: isPriority(record), revision: record.recordChangeTag,
  };
}

function patch(record: CloudKitRecord, mutations: Mutation[]): CloudKitRecord {
  const changed = mutations.find(operation => operation.record.recordName === record.recordName);
  return changed ? { ...record, fields: { ...record.fields, ...changed.record.fields } } : record;
}

function mergeSaved(record: CloudKitRecord, saved: CloudKitRecord[]): CloudKitRecord {
  const response = saved.find(item => item.recordName === record.recordName);
  return response ? { ...record, ...response, fields: { ...record.fields, ...response.fields } } : record;
}
