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
  operationType: 'create' | 'update';
  record: CloudKitRecord;
}

export interface CloudKitFilter {
  fieldName?: string;
  systemFieldName?: string;
  comparator: string;
  fieldValue: CloudKitField;
}

export interface CloudKitQuery {
  recordType: string;
  zoneID: CloudKitZoneID;
  filterBy?: CloudKitFilter[];
  continuationMarker?: string;
  resultsLimit?: number;
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
    const user = results<{ userRecordName?: string }>(body, 'users')[0];
    if (!user?.userRecordName) throw new CloudKitError('UNEXPECTED_SERVER_RESPONSE');
    return { userRecordName: user.userRecordName };
  }

  async listZones(): Promise<CloudKitZone[]> {
    return results(await this.#request('private', 'zones/list'), 'zones');
  }

  async query(options: CloudKitQuery): Promise<{ records: CloudKitRecord[]; continuationMarker?: string }> {
    const { recordType, filterBy, ...request } = options;
    const body = await this.#request('private', 'records/query', {
      ...request,
      query: { recordType, ...(filterBy ? { filterBy } : {}) },
    });
    return {
      records: results(body, 'records'),
      ...(typeof body.continuationMarker === 'string' ? { continuationMarker: body.continuationMarker } : {}),
    };
  }

  async lookup(options: { recordNames: string[]; zoneID: CloudKitZoneID }): Promise<CloudKitRecord[]> {
    if (!options.recordNames.length) return [];
    return results(await this.#request('private', 'records/lookup', {
      zoneID: options.zoneID,
      records: options.recordNames.map(recordName => ({ recordName })),
    }), 'records');
  }

  async modify(options: { operations: CloudKitOperation[]; zoneID: CloudKitZoneID }): Promise<CloudKitRecord[]> {
    if (!options.operations.length) return [];
    for (const operation of options.operations) {
      if (operation.operationType === 'update' && !operation.record.recordChangeTag) {
        throw new CloudKitError('MISSING_RECORD_CHANGE_TAG');
      }
    }
    return results(await this.#request('private', 'records/modify', { ...options, atomic: true }), 'records');
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
    let response: Response;
    try {
      response = await (options.fetch ?? fetch)(url, {
        method: body ? 'POST' : 'GET',
        headers,
        ...(body ? { body: JSON.stringify(body) } : {}),
        redirect: 'manual',
        signal: AbortSignal.timeout(20_000),
      });
    } catch {
      // Fetch errors can contain the credential-bearing URL; never propagate them.
      throw new CloudKitError('NETWORK_ERROR');
    }
    if (response.status >= 300 && response.status < 400) {
      throw new CloudKitError('UNEXPECTED_REDIRECT', response.status);
    }
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
