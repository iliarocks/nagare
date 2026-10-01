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
const origin = 'https://mcp.dev.nagare.page';

test('real Worker enforces OAuth discovery, PKCE, resource binding, and scopes', { timeout: 60_000 }, async () => {
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
    vars: { CLOUDKIT_CONTAINER: 'test-only', CLOUDKIT_ENVIRONMENT: 'development', CLOUDKIT_API_TOKEN: 'unused-test-token' },
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
    const unauthenticated = await request('/mcp');
    assert.equal(unauthenticated.status, 401);
    assert.match(unauthenticated.headers.get('WWW-Authenticate')!, /resource_metadata=/);
    const resource = await json<OAuthProtectedResourceMetadata & { scopes_supported: string[] }>('/.well-known/oauth-protected-resource/mcp');
    assert.equal(resource.resource, `${origin}/mcp`);
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
    assert.equal((await request('/mcp', { headers: { Authorization: 'Bearer invalid' } })).status, 401);

    // Stand in only for successful Apple authentication. The package creates
    // the real grant in the harness's KV; workerd handles the entire protocol.
    const env = await worker.getEnv();
    const oauth = getOAuthApi({
      apiRoute: '/mcp', apiHandler: { fetch: () => new Response() }, defaultHandler: { fetch: () => new Response() },
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
    const wrongResource = await exchange(await issue(['nagare:read', 'nagare:write']), 'https://other.example/mcp');
    assert.equal(wrongResource.status, 400);

    const readOnly = await exchange(await issue(['nagare:read']));
    assert.equal(readOnly.status, 200);
    const readOnlyToken = await readOnly.json() as { access_token: string };
    const denied = await request('/mcp', { headers: { Authorization: `Bearer ${readOnlyToken.access_token}` } });
    assert.equal(denied.status, 403);
    assert.match(denied.headers.get('WWW-Authenticate')!, /insufficient_scope/);

    const tokens = await exchange(await issue(['nagare:read', 'nagare:write', 'offline_access']));
    assert.equal(tokens.status, 200);
    const token = await tokens.json() as { access_token: string; refresh_token: string };
    assert.ok(token.refresh_token);
    const tools = await request('/mcp', {
      method: 'POST', headers: { Authorization: `Bearer ${token.access_token}`, 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream' },
      body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'tools/list', params: {} }),
    });
    const body = await tools.text();
    assert.equal(tools.status, 200, body);
    assert.match(body, /list_projects/);
    assert.match(body, /complete_task/);
    assert.match(body, /securitySchemes/);
  } finally {
    await harness.close();
    await rm(directory, { recursive: true, force: true });
  }
});
