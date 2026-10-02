import { DurableObject } from 'cloudflare:workers';
import type { AuthEnvironment } from './auth.js';
import { CloudKitClient, CloudKitError, type CloudKitRecord, type CloudKitZoneID } from './cloudkit.js';
import { Nagare, NagareError, type CreateTask, type TaskChanges, type TaskQuery, type TaskMove, type RecurrenceChanges } from './nagare.js';
import type { Projects, CreateProject, ProjectChanges, ProjectMove } from './projects.js';

export const ORIGIN = 'https://mcp.dev.nagare.page';

export interface Env extends AuthEnvironment {
  OAUTH_KV: KVNamespace;
  CONNECTIONS: DurableObjectNamespace<Connection>;
  CLOUDKIT_CONTAINER: string;
  CLOUDKIT_ENVIRONMENT: 'development' | 'production';
  CLOUDKIT_API_TOKEN: string;
}

export type Operation =
  | { name: 'list_projects' }
  | { name: 'create_project'; input: CreateProject }
  | { name: 'update_project'; id: string; changes: ProjectChanges; revision: string }
  | { name: 'delete_project'; id: string; revision: string }
  | { name: 'reorder_projects'; input: ProjectMove }
  | { name: 'list_tasks'; options: TaskQuery }
  | { name: 'list_completed_tasks'; options: Omit<TaskQuery, 'date'> }
  | { name: 'create_task'; input: CreateTask }
  | { name: 'update_task'; id: string; changes: TaskChanges; revision: string }
  | { name: 'complete_task'; id: string; revision: string }
  | { name: 'delete_task'; id: string; revision: string }
  | { name: 'reinstate_task'; id: string; revision: string; date?: string }
  | { name: 'reorder_tasks'; input: TaskMove }
  | { name: 'list_recurrences'; options?: { projectId?: string | null } }
  | { name: 'update_recurrence'; id: string; changes: RecurrenceChanges; revision: string }
  | { name: 'stop_recurrence'; id: string; revision: string };

type NagareData = Awaited<ReturnType<
  Projects['list' | 'create' | 'update' | 'delete' | 'reorder']
  | Nagare['listTasks' | 'listCompletedTasks' | 'createTask' | 'updateTask' | 'completeTask'
    | 'deleteTask' | 'reinstateTask' | 'reorderTasks' | 'listRecurrences' | 'updateRecurrence' | 'stopRecurrence']
>>;
export type OperationResult = { ok: true; data: NagareData } | { ok: false; code: string; message: string };
type Settings = { token: string; timeZone: string; zoneID: CloudKitZoneID; expiresAt: number };

export function cloudKit(env: Env, token?: string, saveToken?: (token: string) => Promise<void>) {
  return new CloudKitClient({
    container: env.CLOUDKIT_CONTAINER,
    environment: env.CLOUDKIT_ENVIRONMENT,
    apiToken: env.CLOUDKIT_API_TOKEN,
    origin: ORIGIN,
    webAuthToken: token,
    onWebAuthToken: saveToken,
  });
}

/** Holds credentials only. Task/project records stay in the user's CloudKit database. */
export class Connection extends DurableObject<Env> {
  private queue: Promise<unknown> = Promise.resolve();

  private serialized<T>(action: () => Promise<T>): Promise<T> {
    const result = this.queue.then(action);
    this.queue = result.catch(() => undefined);
    return result;
  }

  private async retain(settings: Omit<Settings, 'expiresAt'>): Promise<void> {
    const expiresAt = Date.now() + 30 * 24 * 60 * 60 * 1000;
    await this.ctx.storage.transaction(async storage => {
      await storage.put('connection', { ...settings, expiresAt });
      await storage.setAlarm(expiresAt);
    });
  }

  alarm(): Promise<void> {
    return this.serialized(async () => {
      const settings = await this.ctx.storage.get<Settings>('connection');
      if (settings && settings.expiresAt > Date.now()) {
        await this.ctx.storage.setAlarm(settings.expiresAt);
        return;
      }
      await this.ctx.storage.deleteAll();
    });
  }

  configure(token: string, timeZone: string): Promise<void> {
    return this.serialized(async () => {
      new Intl.DateTimeFormat('en', { timeZone });
      const client = cloudKit(this.env, token, async rotated => { token = rotated; });
      const zones = await client.listZones();
      const zone = zones.find(value => value.zoneID.zoneName === 'com.apple.coredata.cloudkit.zone');
      if (!zone) throw new Error('Open Nagare with iCloud sync enabled before connecting.');
      await this.retain({ token, timeZone, zoneID: zone.zoneID });
    });
  }

  run(operation: Operation): Promise<OperationResult> {
    return this.serialized(async () => {
      try {
        const settings = await this.ctx.storage.get<Settings>('connection');
        if (!settings || settings.expiresAt <= Date.now()) {
          await this.ctx.storage.deleteAll();
          return { ok: false, code: 'AUTHENTICATION_REQUIRED', message: 'Reconnect Nagare to your agent.' };
        }
        const client = cloudKit(this.env, settings.token, async token => {
          settings.token = token;
          await this.ctx.storage.put('connection', settings);
        });
        let snapshot: Promise<CloudKitRecord[]> | undefined;
        const nagare = new Nagare({
          async list(recordType, text = 'all') {
            snapshot ??= client.snapshot(settings.zoneID);
            const records = (await snapshot).filter(record => record.recordType === recordType
              && record.fields.CD_entityName?.value === recordType.slice(3));
            const needsText = records.filter(record => text === 'all' || (text === 'active' && record.fields.CD_completedAt?.value == null)
              || (text === 'completed' && record.fields.CD_completedAt?.value != null));
            await client.hydrate(needsText);
            return records;
          },
          async lookup(recordName) {
            try {
              return (await client.lookup({ recordNames: [recordName], zoneID: settings.zoneID }))[0];
            } catch (error) {
              if (error instanceof CloudKitError && ['NOT_FOUND', 'UNKNOWN_ITEM'].includes(error.code)) return undefined;
              throw error;
            }
          },
          async modify(operations) {
            try { return await client.modify({ operations, zoneID: settings.zoneID }); }
            finally { snapshot = undefined; }
          },
        }, settings.timeZone);
        let data: NagareData;
        switch (operation.name) {
          case 'list_projects': data = await nagare.listProjects(); break;
          case 'create_project': data = await nagare.projects.create(operation.input); break;
          case 'update_project': data = await nagare.projects.update(operation.id, operation.changes, operation.revision); break;
          case 'delete_project': data = await nagare.projects.delete(operation.id, operation.revision); break;
          case 'reorder_projects': data = await nagare.projects.reorder(operation.input); break;
          case 'list_tasks': data = await nagare.listTasks(operation.options); break;
          case 'list_completed_tasks': data = await nagare.listCompletedTasks(operation.options); break;
          case 'create_task': data = await nagare.createTask(operation.input); break;
          case 'update_task': data = await nagare.updateTask(operation.id, operation.changes, operation.revision); break;
          case 'complete_task': data = await nagare.completeTask(operation.id, operation.revision); break;
          case 'delete_task': data = await nagare.deleteTask(operation.id, operation.revision); break;
          case 'reinstate_task': data = await nagare.reinstateTask(operation.id, operation.revision, operation.date); break;
          case 'reorder_tasks': data = await nagare.reorderTasks(operation.input); break;
          case 'list_recurrences': data = await nagare.listRecurrences(operation.options); break;
          case 'update_recurrence': data = await nagare.updateRecurrence(operation.id, operation.changes, operation.revision); break;
          case 'stop_recurrence': data = await nagare.stopRecurrence(operation.id, operation.revision); break;
        }
        await this.retain(settings);
        return { ok: true, data };
      } catch (error) {
        if (error instanceof NagareError) return { ok: false, code: error.code, message: error.message };
        if (error instanceof CloudKitError) {
          return { ok: false, code: error.code, message: error.code === 'CONFLICT'
            ? 'The item changed. Read it again before deciding what to edit.'
            : error.code === 'TRANSACTION_TOO_LARGE'
              ? 'This operation exceeds CloudKit’s 200-record atomic transaction limit. No records were changed. Use smaller task selections, or perform this bulk operation in Nagare.'
              : `CloudKit could not complete the operation (${error.code}).` };
        }
        return { ok: false, code: 'UNEXPECTED_ERROR', message: 'The operation could not be completed. Read the task before retrying.' };
      }
    });
  }
}
