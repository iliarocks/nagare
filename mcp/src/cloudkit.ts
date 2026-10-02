export type CloudKitValue = string | number | boolean | null | CloudKitValue[] | { [key: string]: CloudKitValue };

export interface CloudKitField {
  // CloudKit dates are milliseconds since 1970, not seconds since Apple's 2001 epoch.
  value: CloudKitValue;
  type?: string;
}

export interface CloudKitRecord {
  recordName: string;
  recordType: string;
  recordChangeTag?: string;
  fields: Record<string, CloudKitField>;
}

export interface CloudKitZoneID {
  zoneName: string;
  ownerRecordName?: string;
}

export interface CloudKitZone {
  zoneID: CloudKitZoneID;
  atomic?: boolean;
  syncToken?: string;
}

export interface CloudKitOperation {
  operationType: 'create' | 'update' | 'delete';
  record: CloudKitRecord;
}

export interface CloudKitFailure {
  serverErrorCode: string;
  recordName?: string;
  retryAfter?: number;
  redirectURL?: string;
}

export class CloudKitError extends Error {
  readonly code: string;
  readonly status: number;
  readonly failures: CloudKitFailure[];

  constructor(code: string, status = 0, failures: CloudKitFailure[] = []) {
    super(`CloudKit request failed (${code}).`);
    this.name = 'CloudKitError';
    this.code = code;
    this.status = status;
    this.failures = failures;
  }

  get redirectURL(): string | undefined {
    return this.failures.find(failure => failure.redirectURL)?.redirectURL;
  }
}

export interface CloudKitOptions {
  container: string;
  environment: 'development' | 'production';
  apiToken: string;
  webAuthToken?: string;
  origin?: string;
  onWebAuthToken?: (token: string) => void | Promise<void>;
  fetch?: typeof fetch;
}

type JSONDictionary = Record<string, unknown>;
const textFields = ['CD_title', 'CD_notes'];
const inlineTextBytes = 128 * 1024;
const maximumAssetBytes = 50 * 1024 * 1024; // CloudKit's documented asset size limit.

function dictionary(value: unknown): value is JSONDictionary {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function failure(value: unknown): CloudKitFailure | undefined {
  if (!dictionary(value) || typeof value.serverErrorCode !== 'string') return;
  const result: CloudKitFailure = { serverErrorCode: value.serverErrorCode };
  if (typeof value.recordName === 'string') result.recordName = value.recordName;
  if (typeof value.retryAfter === 'number') result.retryAfter = value.retryAfter;
  if (typeof value.redirectURL === 'string') result.redirectURL = value.redirectURL;
  return result;
}

function results<T>(body: JSONDictionary, key: string): T[] {
  const values = body[key];
  if (!Array.isArray(values)) throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
  const failures = values.map(failure).filter((value): value is CloudKitFailure => value !== undefined);
  if (failures.length) throw new CloudKitError(failures[0].serverErrorCode, 200, failures);
  return values as T[];
}

/** One client's requests are serialized because CloudKit rotates its web token.
 * Callers must also serialize access to each user's persisted token across requests.
 */
export class CloudKitClient {
  #options: CloudKitOptions;
  #webAuthToken?: string;
  #queue: Promise<void> = Promise.resolve();

  constructor(options: CloudKitOptions) {
    this.#options = options;
    this.#webAuthToken = options.webAuthToken;
  }

  async currentUser(): Promise<{ userRecordName: string }> {
    const body = await this.#request('public', 'users/caller');
    if (typeof body.userRecordName !== 'string' || !body.userRecordName) throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
    return { userRecordName: body.userRecordName };
  }

  async listZones(): Promise<CloudKitZone[]> {
    return results(await this.#request('private', 'zones/list'), 'zones');
  }

  /** Initial zone sync reads current records without waiting for query indexes.
   * The cursor lives only for this fetch; no task data or sync state is retained.
   */
  async snapshot(zoneID: CloudKitZoneID): Promise<CloudKitRecord[]> {
    const records = new Map<string, CloudKitRecord>();
    const cursors = new Set<string>();
    let syncToken: string | undefined;
    for (;;) {
      const zones = results<JSONDictionary>(await this.#request('private', 'changes/zone', {
        zones: [{ zoneID, ...(syncToken ? { syncToken } : {}) }],
      }), 'zones');
      const zone = zones[0];
      if (zones.length !== 1 || !dictionary(zone) || !dictionary(zone.zoneID)
        || zone.zoneID.zoneName !== zoneID.zoneName || typeof zone.moreComing !== 'boolean') {
        throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
      }
      for (const record of results<JSONDictionary>(zone, 'records')) {
        if (!dictionary(record) || typeof record.recordName !== 'string' || !record.recordName) {
          throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
        }
        if (record.deleted === true) records.delete(record.recordName);
        else {
          if (typeof record.recordType !== 'string' || !dictionary(record.fields)) throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
          records.set(record.recordName, record as unknown as CloudKitRecord);
        }
      }
      if (!zone.moreComing) break;
      if (typeof zone.syncToken !== 'string' || !zone.syncToken || cursors.has(zone.syncToken)) {
        throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
      }
      syncToken = zone.syncToken;
      cursors.add(syncToken);
    }
    return [...records.values()];
  }

  async lookup(options: { recordNames: string[]; zoneID: CloudKitZoneID }): Promise<CloudKitRecord[]> {
    if (!options.recordNames.length) return [];
    return this.hydrate(results(await this.#request('private', 'records/lookup', {
      zoneID: options.zoneID,
      records: options.recordNames.map(recordName => ({ recordName })),
    }), 'records'));
  }

  async modify(options: { operations: CloudKitOperation[]; zoneID: CloudKitZoneID }): Promise<CloudKitRecord[]> {
    if (!options.operations.length) return [];
    if (options.operations.length > 200) throw new CloudKitError('TRANSACTION_TOO_LARGE');
    for (const operation of options.operations) {
      if (operation.operationType !== 'create' && !operation.record.recordChangeTag) {
        throw new CloudKitError('MISSING_RECORD_CHANGE_TAG');
      }
      if (operation.operationType !== 'delete' && textFields.some(field => {
        const asset = operation.record.fields[`${field}_ckAsset`]?.value;
        return dictionary(asset) && 'downloadURL' in asset;
      })) throw new CloudKitError('READ_ONLY_ASSET');
    }
    const operations = [];
    for (const operation of options.operations) {
      const { recordName, recordType, recordChangeTag } = operation.record;
      if (operation.operationType === 'delete') {
        operations.push({ operationType: 'delete', record: { recordName, recordChangeTag } });
        continue;
      }
      const fields = { ...operation.record.fields };
      for (const field of textFields) {
        const value = fields[field]?.value;
        if (value !== null && typeof value !== 'string') continue;
        const assetField = `${field}_ckAsset`;
        if (value === null && fields[assetField]?.value != null) continue;
        fields[assetField] = { value: null };
        if (value === null) continue;
        if (new TextEncoder().encode(JSON.stringify(value)).byteLength <= inlineTextBytes) continue;
        const tokens = results<JSONDictionary>(await this.#request('private', 'assets/upload', {
          zoneID: options.zoneID, tokens: [{ recordName, recordType, fieldName: assetField }],
        }), 'tokens');
        const token = tokens[0];
        if (tokens.length !== 1 || token?.recordName !== recordName || token?.fieldName !== assetField) {
          throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
        }
        const file = new Blob([value], { type: 'text/plain;charset=utf-8' });
        const response = await this.#asset(token.url, file);
        let body: unknown;
        try { body = await response.json(); } catch { throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE'); }
        const asset = dictionary(body) && body.singleFile;
        if (!dictionary(asset) || asset.size !== file.size ||
          !['wrappingKey', 'fileChecksum', 'receipt', 'referenceChecksum'].every(key => typeof asset[key] === 'string')) {
          throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
        }
        // Core Data imports a present inline value before considering its asset.
        fields[field] = { value: null };
        fields[assetField] = { value: asset as CloudKitValue };
      }
      operations.push({ ...operation, record: { ...operation.record, fields } });
    }
    const records = results<CloudKitRecord & { deleted?: boolean }>(await this.#request('private', 'records/modify', {
      operations, zoneID: options.zoneID, atomic: true,
    }), 'records');
    if (records.length !== operations.length || operations.some(operation => {
      const matches = records.filter(record => record.recordName === operation.record.recordName);
      return matches.length !== 1 || (matches[0].deleted === true) !== (operation.operationType === 'delete');
    })) throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
    // Return acknowledged patches. Callers merge them with their read snapshot;
    // no asset request can fail after the transaction has already committed.
    return records.filter(record => !record.deleted).map(record => {
      if (typeof record.recordChangeTag !== 'string' || !record.recordChangeTag) throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
      const original = options.operations.find(operation => operation.record.recordName === record.recordName)!.record;
      return { ...original, recordChangeTag: record.recordChangeTag };
    });
  }

  async hydrate(records: CloudKitRecord[]): Promise<CloudKitRecord[]> {
    for (const record of records) {
      if (!dictionary(record.fields)) throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
      for (const field of textFields) {
        const value = record.fields[field]?.value;
        const asset = record.fields[`${field}_ckAsset`]?.value;
        if (value !== undefined && value !== null) {
          if (typeof value === 'string' && asset != null) record.fields[`${field}_ckAsset`] = { value: null };
          continue;
        }
        if (asset == null) continue;
        if (!dictionary(asset) || typeof asset.size !== 'number' || !Number.isSafeInteger(asset.size) || asset.size < 0) {
          throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
        }
        if (asset.size > maximumAssetBytes) throw new CloudKitError('ASSET_TOO_LARGE');
        const response = await this.#asset(asset.downloadURL);
        const reader = response.body?.getReader();
        if (!reader) throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
        const decoder = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true });
        let size = 0;
        let text = '';
        try {
          for (;;) {
            const chunk = await reader.read();
            if (chunk.done) break;
            size += chunk.value.byteLength;
            if (size > maximumAssetBytes) throw new CloudKitError('ASSET_TOO_LARGE');
            text += decoder.decode(chunk.value, { stream: true });
          }
          text += decoder.decode();
          if (size !== asset.size) throw new CloudKitError('ASSET_SIZE_MISMATCH');
        } catch (error) {
          await reader.cancel().catch(() => {});
          throw error instanceof CloudKitError ? error : new CloudKitError('INVALID_TEXT_ASSET');
        } finally { reader.releaseLock(); }
        record.fields[field] = { value: text };
        // The public record view contains hydrated text, including valid empty text.
        record.fields[`${field}_ckAsset`] = { value: null };
      }
    }
    return records;
  }

  async #asset(value: unknown, body?: Blob): Promise<Response> {
    let url: URL;
    try { url = new URL(typeof value === 'string' ? value : ''); }
    catch { throw new CloudKitError('INVALID_ASSET_URL'); }
    const domains = ['icloud-content.com', 'icloud.com', 'icloud.com.cn', 'apple-cloudkit.com', 'cdn-apple.com'];
    if (url.protocol !== 'https:' || url.username || url.password || url.port ||
      !domains.some(domain => url.hostname === domain || url.hostname.endsWith(`.${domain}`))) {
      throw new CloudKitError('INVALID_ASSET_URL');
    }
    // Workers has no cookie jar. Only the signed URL authorizes this request.
    const response = await this.#fetch(url, { method: body ? 'POST' : 'GET', ...(body ? { body } : {}) });
    if (!response.ok) throw new CloudKitError('ASSET_HTTP_ERROR', response.status);
    return response;
  }

  async #fetch(url: URL, init: RequestInit): Promise<Response> {
    let response: Response;
    try {
      response = await (this.#options.fetch ?? fetch)(url, { ...init, redirect: 'manual', signal: AbortSignal.timeout(20_000) });
    } catch {
      // Fetch errors can contain the credential-bearing URL; never propagate them.
      throw new CloudKitError('NETWORK_ERROR');
    }
    if (response.status >= 300 && response.status < 400) throw new CloudKitError('UNEXPECTED_REDIRECT', response.status);
    return response;
  }

  #request(database: 'public' | 'private', path: string, body?: JSONDictionary): Promise<JSONDictionary> {
    const request = this.#queue.then(() => this.#perform(database, path, body));
    this.#queue = request.then(() => undefined, () => undefined);
    return request;
  }

  async #perform(database: string, path: string, body?: JSONDictionary): Promise<JSONDictionary> {
    const options = this.#options;
    const url = new URL(`https://api.apple-cloudkit.com/database/1/${encodeURIComponent(options.container)}/${options.environment}/${database}/${path}`);
    url.searchParams.set('ckAPIToken', options.apiToken);
    if (this.#webAuthToken) url.searchParams.set('ckWebAuthToken', this.#webAuthToken);
    const headers: Record<string, string> = { Accept: 'application/json' };
    if (body) headers['Content-Type'] = 'text/plain';
    if (options.origin) headers.Origin = options.origin;
    const response = await this.#fetch(url, {
      method: body ? 'POST' : 'GET', headers, ...(body ? { body: JSON.stringify(body) } : {}),
    });
    // These are the headers used by Apple's current CloudKit JS client.
    const token = response.headers.get('x-apple-cloudkit-web-auth-token') ?? response.headers.get('x-apple-cloudkit-session');
    if (token) {
      this.#webAuthToken = token;
      try {
        await options.onWebAuthToken?.(token);
      } catch {
        throw new CloudKitError('AUTH_PERSIST_ERROR', response.status);
      }
    }
    let data: unknown;
    try {
      data = await response.json();
    } catch {
      throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE', response.status);
    }
    if (!dictionary(data)) throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE', response.status);
    const error = failure(data);
    if (error) throw new CloudKitError(error.serverErrorCode, response.status, [error]);
    if (!response.ok) throw new CloudKitError('HTTP_ERROR', response.status);
    return data;
  }
}
