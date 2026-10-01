import { DurableObject } from 'cloudflare:workers';
import type { AuthEnvironment } from './auth.js';
import { CloudKitClient, CloudKitError, type CloudKitRecord, type CloudKitZoneID } from './cloudkit.js';
import { Nagare, NagareError, type CreateTask, type TaskChanges } from './nagare.js';

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
  | { name: 'list_tasks'; options: { completed?: boolean; projectId?: string; date?: string } }
  | { name: 'create_task'; input: CreateTask }
  | { name: 'update_task'; id: string; changes: TaskChanges; revision: string }
  | { name: 'complete_task'; id: string; revision: string };

type NagareData = Awaited<ReturnType<Nagare['listProjects'] | Nagare['listTasks'] | Nagare['createTask'] | Nagare['updateTask'] | Nagare['completeTask']>>;
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
        const nagare = new Nagare({
          async list(recordType) {
            const records: CloudKitRecord[] = [];
            let continuationMarker: string | undefined;
            do {
              const page = await client.query({
                recordType, zoneID: settings.zoneID, continuationMarker,
                filterBy: [{ fieldName: 'CD_entityName', comparator: 'EQUALS', fieldValue: { value: recordType.slice(3), type: 'STRING' } }],
              });
              records.push(...page.records);
              continuationMarker = page.continuationMarker;
            } while (continuationMarker);
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
          modify: operations => client.modify({ operations, zoneID: settings.zoneID }),
        }, settings.timeZone);
        let data: NagareData;
        switch (operation.name) {
          case 'list_projects': data = await nagare.listProjects(); break;
          case 'list_tasks': data = await nagare.listTasks(operation.options); break;
          case 'create_task': data = await nagare.createTask(operation.input); break;
          case 'update_task': data = await nagare.updateTask(operation.id, operation.changes, operation.revision); break;
          case 'complete_task': data = await nagare.completeTask(operation.id, operation.revision); break;
        }
        await this.retain(settings);
        return { ok: true, data };
      } catch (error) {
        if (error instanceof NagareError) return { ok: false, code: error.code, message: error.message };
        if (error instanceof CloudKitError) {
          return { ok: false, code: error.code, message: error.code === 'CONFLICT'
            ? 'The task changed. Read it again before deciding what to edit.'
            : `CloudKit could not complete the operation (${error.code}).` };
        }
        return { ok: false, code: 'UNEXPECTED_ERROR', message: 'The operation could not be completed. Read the task before retrying.' };
      }
    });
  }
}
