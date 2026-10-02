import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { registerHooks } from 'node:module';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createTestHarness } from 'wrangler';
import type { OAuthProtectedResourceMetadata } from '@cloudflare/workers-oauth-provider';

// The helper only needs KV and Web Crypto; WorkerEntrypoint is unused here.
registerHooks({ resolve(specifier, context, next) {
  return specifier === 'cloudflare:workers'
    ? { url: 'data:text/javascript,export class WorkerEntrypoint {}', shortCircuit: true }
    : next(specifier, context);
} });
const { getOAuthApi } = await import('@cloudflare/workers-oauth-provider');
for (const [environment, origin, name] of [
  ['development', 'https://mcp.development.nagare.page', 'Nagare Development'],
  ['production', 'https://mcp.nagare.page', 'Nagare'],
] as const) test(`${environment} Worker enforces OAuth discovery, PKCE, resource binding, and scopes`, { timeout: 60_000 }, async () => {
  const metadataPath = '/.well-known/oauth-protected-resource';
  const directory = await mkdtemp(join(tmpdir(), 'nagare-oauth-test-'));
  const entrypoint = join(directory, 'worker.ts');
  const source = fileURLToPath(new URL('../src/index.ts', import.meta.url).href);
  // The local harness rewrites Host to 127.0.0.1. Restore the URL's host as the
  // edge does, so the MCP SDK can perform its normal DNS-rebinding check.
  await writeFile(entrypoint, `import worker from ${JSON.stringify(source)};
    export { Connection } from ${JSON.stringify(source)};
    export default { fetch(request, env, ctx) {
      const headers = new Headers(request.headers);
      headers.set('Host', new URL(request.url).host);
      return worker.fetch(new Request(request, { headers }), env, ctx);
    } };`);
  const harness = createTestHarness({ workers: [{ config: {
    name: 'nagare-oauth-test',
    main: entrypoint,
    compatibility_date: '2026-10-01',
    compatibility_flags: ['nodejs_compat', 'global_fetch_strictly_public'],
    vars: { CLOUDKIT_CONTAINER: 'test-only', CLOUDKIT_ENVIRONMENT: environment, CLOUDKIT_API_TOKEN: 'unused-test-token' },
    kv_namespaces: [{ binding: 'OAUTH_KV' }],
    durable_objects: { bindings: [{ name: 'CONNECTIONS', class_name: 'Connection' }] },
    migrations: [{ tag: 'v1', new_sqlite_classes: ['Connection'] }],
  } }] });
  try {
    await harness.listen();
    const worker = harness.getWorker<{ OAUTH_KV: KVNamespace }>();
    const service = await worker.getExport();
    const request = (path: string, init?: RequestInit) => service.fetch(`${origin}${path}`, init);
    const json = async <T>(path: string): Promise<T> => {
      const response = await request(path);
      assert.equal(response.status, 200);
      return response.json() as Promise<T>;
    };
    const unauthenticated = await request('/');
    assert.equal(unauthenticated.status, 401);
    assert.match(unauthenticated.headers.get('WWW-Authenticate')!, /resource_metadata=/);
    const resource = await json<OAuthProtectedResourceMetadata & { scopes_supported: string[] }>(metadataPath);
    assert.equal(resource.resource, origin);
    assert.equal(resource.resource_name, name);
    assert.deepEqual(resource.authorization_servers, [origin]);
    assert.deepEqual(resource.scopes_supported, ['nagare:read', 'nagare:write']);
    const metadata = await json<{
      issuer: string; authorization_endpoint: string; token_endpoint: string;
      code_challenge_methods_supported: string[]; scopes_supported: string[];
      client_id_metadata_document_supported: boolean; authorization_response_iss_parameter_supported: boolean;
    }>('/.well-known/oauth-authorization-server');
    assert.equal(metadata.issuer, origin);
    assert.ok(metadata.code_challenge_methods_supported.includes('S256'));
    assert.equal(metadata.client_id_metadata_document_supported, true);
    assert.equal(metadata.authorization_response_iss_parameter_supported, true);
    assert.equal((await request('/auth.js')).status, 200);
    assert.equal((await request('/mcp')).status, 404);
    const invalidCallback = await request('/callback', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ state: 'invalid', token: 'unused-token' }),
    });
    assert.equal(invalidCallback.status, 400, await invalidCallback.text());

    const registration = await request('/oauth/register', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({
        client_name: 'Local integration test', redirect_uris: ['https://client.example/callback'],
        token_endpoint_auth_method: 'none', grant_types: ['authorization_code', 'refresh_token'], response_types: ['code'],
      }),
    });
    assert.equal(registration.status, 201);
    const client = await registration.json() as { client_id: string };
    const verifier = 'a'.repeat(64);
    const challenge = Buffer.from(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))).toString('base64url');
    const params = new URLSearchParams({
      client_id: client.client_id, redirect_uri: 'https://client.example/callback', response_type: 'code',
      resource: resource.resource, scope: 'nagare:read nagare:write offline_access', state: 'client-state',
      code_challenge: challenge, code_challenge_method: 'S256',
    });
    const consent = await request(`/authorize?${params}`);
    assert.equal(consent.status, 200);
    assert.match(await consent.text(), /Connect with iCloud/);
    assert.ok(consent.headers.get('Set-Cookie'));
    for (const [field, value] of [['code_challenge_method', 'plain'], ['redirect_uri', 'https://attacker.example/callback']]) {
      const malformed = new URLSearchParams(params);
      malformed.set(field, value);
      assert.equal((await request(`/authorize?${malformed}`)).status, 400, field);
    }
    const withoutPKCE = new URLSearchParams(params);
    withoutPKCE.delete('code_challenge');
    assert.equal((await request(`/authorize?${withoutPKCE}`)).status, 400);
    assert.equal((await request('/', { headers: { Authorization: 'Bearer invalid' } })).status, 401);

    // Stand in only for successful Apple authentication. The package creates
    // the real grant in the harness's KV; workerd handles the entire protocol.
    const env = await worker.getEnv();
    const oauth = getOAuthApi({
      apiRoute: '/', apiHandler: { fetch: () => new Response() }, defaultHandler: { fetch: () => new Response() },
      authorizeEndpoint: metadata.authorization_endpoint, tokenEndpoint: metadata.token_endpoint,
      scopesSupported: metadata.scopes_supported, resourceMetadata: resource,
    }, env);
    const issue = async (scope: string[]) => {
      const auth = await oauth.parseAuthRequest(new Request(`${origin}/authorize?${params}`));
      const result = await oauth.completeAuthorization({ request: auth, userId: 'test-user', metadata: {}, scope, props: { connectionId: 'test-user' } });
      assert.equal(new URL(result.redirectTo).searchParams.get('iss'), origin);
      return new URL(result.redirectTo).searchParams.get('code')!;
    };
    const exchange = (code: string, resourceURL = resource.resource, codeVerifier = verifier) => request('/oauth/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'authorization_code', client_id: client.client_id,
        redirect_uri: 'https://client.example/callback', code, code_verifier: codeVerifier, resource: resourceURL }).toString(),
    });
    const wrongVerifier = await exchange(await issue(['nagare:read', 'nagare:write']), resource.resource, 'b'.repeat(64));
    assert.equal(wrongVerifier.status, 400);
    const otherEnvironment = environment === 'development' ? 'https://mcp.nagare.page' : 'https://mcp.development.nagare.page';
    const wrongResource = await exchange(await issue(['nagare:read', 'nagare:write']), otherEnvironment);
    assert.equal(wrongResource.status, 400);

    const readOnly = await exchange(await issue(['nagare:read']));
    assert.equal(readOnly.status, 200);
    const readOnlyToken = await readOnly.json() as { access_token: string };
    const denied = await request('/', { headers: { Authorization: `Bearer ${readOnlyToken.access_token}` } });
    assert.equal(denied.status, 403);
    assert.match(denied.headers.get('WWW-Authenticate')!, /insufficient_scope/);

    const tokens = await exchange(await issue(['nagare:read', 'nagare:write', 'offline_access']));
    assert.equal(tokens.status, 200);
    const token = await tokens.json() as { access_token: string; refresh_token: string };
    assert.ok(token.refresh_token);
    const rpc = (method: string, params: unknown = {}) => request('/', {
      method: 'POST', headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }),
    });
    const initialized = await rpc('initialize', {
      protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'integration-test', version: '1' },
    });
    assert.equal(initialized.status, 200);
    assert.match(await initialized.text(), new RegExp(`"name":"${name}"`));
    const disconnected = await rpc('tools/call', { name: 'list_projects', arguments: {} });
    const disconnectedBody = await disconnected.text();
    assert.equal(disconnected.status, 200);
    assert.ok(disconnectedBody.includes(origin + metadataPath));
    assert.match(disconnectedBody, /AUTHENTICATION_REQUIRED/);
    const tools = await rpc('tools/list');
    const body = await tools.text();
    assert.equal(tools.status, 200, body);
    const message = JSON.parse(body.trim().startsWith('{') ? body : body.split('\n').find(line => line.startsWith('data: '))!.slice(6)) as {
      result: { tools: { name: string; description: string; inputSchema: {
        properties: Record<string, { maxLength?: number; properties?: Record<string, unknown> }>;
      }; annotations: Record<string, boolean>; _meta: { securitySchemes: unknown } }[] };
    };
    const definitions = new Map(message.result.tools.map(tool => [tool.name, tool]));
    assert.deepEqual([...definitions.keys()].sort(), [
      'list_projects', 'create_project', 'update_project', 'delete_project', 'reorder_projects',
      'list_tasks', 'list_completed_tasks', 'create_task', 'update_task', 'complete_task',
      'delete_task', 'reinstate_task', 'reorder_tasks', 'list_recurrences', 'update_recurrence', 'stop_recurrence',
    ].sort());
    for (const tool of definitions.values()) {
      assert.deepEqual(tool._meta.securitySchemes, [{ type: 'oauth2', scopes: ['nagare:read', 'nagare:write'] }]);
      assert.equal(tool.annotations.readOnlyHint, tool.name.startsWith('list_'), tool.name);
      assert.equal(tool.annotations.destructiveHint, tool.name.startsWith('delete_'), tool.name);
      assert.equal(tool.annotations.openWorldHint, false, tool.name);
      if (!tool.name.startsWith('list_')) assert.equal(tool.annotations.idempotentHint, true, tool.name);
    }
    const active = definitions.get('list_tasks')!;
    assert.equal('completed' in active.inputSchema.properties, false);
    assert.deepEqual(Object.keys(active.inputSchema.properties).sort(), ['date', 'from', 'through', 'projectId', 'query'].sort());
    assert.deepEqual(Object.keys(definitions.get('list_completed_tasks')!.inputSchema.properties).sort(), ['from', 'through', 'projectId', 'query'].sort());
    assert.match(active.description, /projected/i);
    assert.match(active.description, /read-only/);
    assert.match(definitions.get('delete_project')!.description, /retained/);
    assert.match(definitions.get('stop_recurrence')!.description, /Retains/);
    assert.ok(definitions.get('create_task')!.inputSchema.properties.recurrence);
    assert.ok(definitions.get('update_task')!.inputSchema.properties.changes.properties!.recurrence);
    assert.equal(definitions.get('create_task')!.inputSchema.properties.title.maxLength, undefined);
    assert.equal(definitions.get('create_project')!.inputSchema.properties.notes.maxLength, undefined);

    // Input validation runs before the unconfigured connection is invoked.
    const id = 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA';
    for (const context of [{}, { date: '2026-10-02', projectId: id }]) {
      const invalid = await rpc('tools/call', { name: 'reorder_tasks', arguments: { ids: [id], revisions: { [id]: 'v1' }, ...context } });
      const error = await invalid.text();
      assert.equal(invalid.status, 200, error);
      assert.match(error, /Choose exactly one list context/);
      assert.doesNotMatch(error, /AUTHENTICATION_REQUIRED/);
    }
  } finally {
    await harness.close();
    await rm(directory, { recursive: true, force: true });
  }
});
