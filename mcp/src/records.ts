import type { CloudKitRecord, CloudKitValue } from './cloudkit.js';

export type Fields = CloudKitRecord['fields'];
export type RecordType = 'CD_Todo' | 'CD_Project' | 'CD_RecurrenceTemplate';
export type Mutation = { operationType: 'create' | 'update' | 'delete'; record: CloudKitRecord };
export type TextScope = 'all' | 'active' | 'completed' | 'none';
export interface Store {
  list(type: RecordType, text?: TextScope): Promise<CloudKitRecord[]>;
  lookup(recordName: string): Promise<CloudKitRecord | undefined>;
  modify(operations: Mutation[]): Promise<CloudKitRecord[]>;
}
export type Snapshot = { tasks: CloudKitRecord[]; projects: CloudKitRecord[]; templates: CloudKitRecord[] };
export class NagareError extends Error {
  constructor(public readonly code: string, message: string) { super(message); this.name = 'NagareError'; }
}

export function field(value: CloudKitValue, type?: string): Fields[string] {
  return type ? { value, type } : { value };
}

export function value(record: CloudKitRecord | undefined, key: string) {
  return record?.fields[`CD_${key}`]?.value ?? null;
}

export function text(record: CloudKitRecord | undefined, key: string): string | null {
  const result = value(record, key);
  if ((result === null || result === '') && value(record, `${key}_ckAsset`) != null) {
    throw new NagareError('EXTERNAL_TEXT', `The ${key} text could not be loaded. Read the item again before editing it.`);
  }
  if (result !== null && typeof result !== 'string') throw new NagareError('INVALID_RECORD', `Unexpected ${key} field type.`);
  return result;
}

export function number(record: CloudKitRecord, key: string): number {
  const result = value(record, key);
  if (typeof result !== 'number' || !Number.isFinite(result)) throw new NagareError('INVALID_RECORD', `Missing or invalid ${key}.`);
  return result;
}

export function uuid(value: string) {
  if (!/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value)) {
    throw new NagareError('INVALID_ID', 'Use a UUID for the task or project ID.');
  }
  return value.toUpperCase();
}

export function id(record: CloudKitRecord) { return uuid(text(record, 'id') ?? ''); }

export function unique(records: CloudKitRecord[]) {
  const ids = new Set<string>();
  for (const record of records) {
    const key = id(record);
    if (ids.has(key)) throw new NagareError('SYNC_PENDING', 'Nagare has duplicate records awaiting sync reconciliation. Open the app before editing them here.');
    ids.add(key);
  }
  return records;
}

export function mutable(record: CloudKitRecord, expectedRevision?: string) {
  if (!record.recordChangeTag || (expectedRevision !== undefined && record.recordChangeTag !== expectedRevision)) {
    throw new NagareError('CONFLICT', 'The task changed. Read it again before applying this edit.');
  }
}

export function update(record: CloudKitRecord, fields: Fields): Mutation {
  if (!record.recordChangeTag) throw new NagareError('CONFLICT', 'The record has no revision for a safe update.');
  return { operationType: 'update', record: {
    recordName: record.recordName, recordType: record.recordType, recordChangeTag: record.recordChangeTag, fields,
  } };
}

export function setText(fields: Fields, key: string, value: string | null) {
  fields[`CD_${key}`] = field(value);
  fields[`CD_${key}_ckAsset`] = field(null);
}

export function byOrder(key: string) {
  return (a: CloudKitRecord, b: CloudKitRecord) => {
    const left = text(a, key) ?? (key === 'order' ? '' : null);
    const right = text(b, key) ?? (key === 'order' ? '' : null);
    if (left !== right) return left === null ? 1 : right === null ? -1 : left < right ? -1 : 1;
    return id(a) === id(b) ? 0 : id(a) < id(b) ? -1 : 1;
  };
}

export function validOrder(order: string | null): order is string { return order !== null && /^[0-9a-z]+$/.test(order); }

// The append case of Nagare's FractionalIndex.between(previous, nil).
export function after(previous: string | null): string {
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  let prefix = '';
  for (const digit of previous ?? '') {
    const index = digits.indexOf(digit);
    if (index + 1 < digits.length) return prefix + digits[Math.floor((index + digits.length) / 2)];
    prefix += digit;
  }
  return prefix + 'i';
}

export function mergeMutations(repairs: Mutation[]) {
  const merged = new Map<string, Mutation>();
  for (const repair of repairs) {
    const existing = merged.get(repair.record.recordName);
    if (existing?.operationType === 'delete') continue;
    if (existing && repair.operationType !== 'delete') {
      existing.record.fields = { ...existing.record.fields, ...repair.record.fields };
    } else merged.set(repair.record.recordName, { ...repair, record: { ...repair.record, fields: { ...repair.record.fields } } });
  }
  return [...merged.values()];
}

export function deletion(record: CloudKitRecord): Mutation {
  mutable(record);
  return { operationType: 'delete', record: { ...record, fields: {} } };
}

export function nextOrder(records: CloudKitRecord[], key: string, repairs: Mutation[], now: number): string {
  const sorted = [...records].sort(byOrder(key));
  if (sorted.every(record => validOrder(text(record, key)))) return after(text(sorted.at(-1), key));
  const keys = balancedKeys(sorted.length);
  sorted.forEach((record, index) => repairs.push(update(record, {
    [`CD_${key}`]: field(keys[index]), CD_modifiedAt: field(now, 'TIMESTAMP'),
  })));
  return after(keys.at(-1) ?? null);
}

export function balancedKeys(count: number): string[] {
  const step = (36n ** 12n - 1n) / BigInt(count + 1);
  return Array.from({ length: count }, (_, index) => (step * BigInt(index + 1)).toString(36).padStart(12, '0'));
}

export function between(lower: string | null, upper: string | null): string | null {
  if ((lower !== null && !validOrder(lower)) || (upper !== null && !validOrder(upper)) || (lower !== null && upper !== null && lower >= upper)) return null;
  const digits = '0123456789abcdefghijklmnopqrstuvwxyz';
  let result = '';
  let high = upper ?? '';
  for (let index = 0; ; index++) {
    const left = index < (lower?.length ?? 0) ? digits.indexOf(lower![index]) : 0;
    const right = index < high.length ? digits.indexOf(high[index]) : digits.length;
    if (left + 1 < right) {
      result += digits[Math.floor((left + right) / 2)];
      return (!lower || lower < result) && (!upper || result < upper) ? result : null;
    }
    result += digits[left];
    if (left < right) high = '';
  }
}

/** Insert a selected block using fractional keys; repair only if no keys fit. */
export function moveOrder(destination: CloudKitRecord[], selected: CloudKitRecord[], beforeId: string | null, key: string, now: number): Mutation[] {
  const selectedIDs = new Set(selected.map(id));
  if (selectedIDs.size !== selected.length || !selected.length) throw new NagareError('INVALID_MOVE', 'Select each item once.');
  const remaining = destination.filter(record => !selectedIDs.has(id(record))).sort(byOrder(key));
  const index = beforeId === null ? remaining.length : remaining.findIndex(record => id(record) === uuid(beforeId));
  if (index < 0) throw new NagareError('INVALID_MOVE', 'The destination item must be in the target list and outside the selection.');
  const upper = text(remaining[index], key);
  let lower = text(remaining[index - 1], key);
  const keys: string[] = [];
  for (const _ of selected) {
    const next = between(lower, upper);
    if (next === null) break;
    keys.push(next); lower = next;
  }
  const ordered = [...remaining.slice(0, index), ...selected, ...remaining.slice(index)];
  const repaired = remaining.some(record => !validOrder(text(record, key))) || keys.length !== selected.length;
  const records = repaired ? ordered : selected;
  const orders = repaired ? balancedKeys(ordered.length) : keys;
  return records.flatMap((record, index) => value(record, key) === orders[index] ? [] : [update(record, {
    [`CD_${key}`]: field(orders[index]), CD_modifiedAt: field(now, 'TIMESTAMP'),
  })]);
}

export function validateText(changes: { title?: string; notes?: string | null }): void {
  if (changes.title !== undefined && !changes.title.trim()) throw new NagareError('INVALID_TITLE', 'Use a nonempty title.');
}
