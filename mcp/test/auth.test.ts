import assert from 'node:assert/strict';
import test from 'node:test';
import { registerHooks } from 'node:module';
import { runInNewContext } from 'node:vm';
import type { AuthRequest, ConsentDescription, OAuthHelpers } from '@cloudflare/workers-oauth-provider';

// These route tests inject the OAuth helpers; only the package's error class is
// executed, so its unused WorkerEntrypoint import needs no Workers runtime.
registerHooks({ resolve(specifier, context, next) {
  return specifier === 'cloudflare:workers'
    ? { url: 'data:text/javascript,export class WorkerEntrypoint {}', shortCircuit: true }
    : next(specifier, context);
} });
const { createAuthHandler, OAUTH_SCOPES } = await import('../src/auth.js');

const origin = 'https://nagare-mcp-dev.example.workers.dev';
const authRequest = { clientId: 'client', redirectUri: 'https://chatgpt.com/callback', scope: OAUTH_SCOPES } as AuthRequest;
const client: ConsentDescription = {
  clientId: 'client', clientName: 'ChatGPT', redirectUri: authRequest.redirectUri,
  redirectHost: 'chatgpt.com', redirectIsLoopback: false, scope: OAUTH_SCOPES,
};

function setup(overrides: Partial<OAuthHelpers> = {}) {
  const calls: { connection?: unknown[]; grant?: unknown; resumed?: Request } = {};
  const oauth = {
    parseAuthRequest: async () => authRequest,
    describeConsent: async () => client,
    beginConsent: async () => ({ handle: 'consent', headers: new Headers({ 'Set-Cookie': 'binding=yes' }) }),
    approveConsent: async (_request, _handle, options) => ({ request: { ...authRequest, scope: options?.scope ?? [] }, headers: new Headers() }),
    beginUpstream: async () => ({ state: 'upstream-state', headers: new Headers({ 'Set-Cookie': 'upstream=yes' }) }),
    finishUpstream: async request => {
      calls.resumed = request;
      return { request: authRequest, data: { timezone: 'America/Los_Angeles' }, headers: new Headers() };
    },
    completeAuthorization: async grant => { calls.grant = grant; return { redirectTo: authRequest.redirectUri }; },
    ...overrides,
  } as OAuthHelpers;
  const handler = createAuthHandler({
    getAppleSignInURL: async () => 'https://idmsa.apple.com/signin',
    connect: async (...args: unknown[]) => {
      calls.connection = args;
      return { connectionId: 'connection-123', userId: 'verified-user' };
    },
  });
  return { handler, env: { OAUTH_PROVIDER: oauth }, calls };
}

test('consent escapes client metadata and preserves browser binding headers', async () => {
  const { handler, env } = setup({ describeConsent: async () => ({ ...client, clientName: '<script>bad</script>' }) });
  const response = await handler.fetch(new Request(`${origin}/authorize`), env);
  const html = await response.text();
  assert.ok(html.includes('&lt;script&gt;bad&lt;/script&gt;'));
  assert.equal(response.headers.get('Set-Cookie'), 'binding=yes');
  assert.ok(response.headers.get('Content-Security-Policy')?.includes("frame-ancestors 'none'"));
  assert.ok(html.includes('chatgpt.com'));
});

test('rejects callbacks from another origin before consuming state or using a token', async () => {
  const { handler, env, calls } = setup();
  const response = await handler.fetch(new Request(`${origin}/callback`, {
    method: 'POST', headers: { Origin: 'https://attacker.example' }, body: JSON.stringify({ state: 'upstream-state', token: 'private-token' }),
  }), env);
  assert.equal(response.status, 400);
  assert.equal(calls.resumed, undefined);
  assert.equal(calls.connection, undefined);
});

test('callback verifies the bound state, connects the user, and grants only a connection ID', async () => {
  const { handler, env, calls } = setup();
  const response = await handler.fetch(new Request(`${origin}/callback`, {
    method: 'POST', headers: { Origin: origin, Cookie: 'upstream=yes' }, body: JSON.stringify({ state: 'upstream-state', token: 'private-token' }),
  }), env);
  assert.equal(response.status, 200);
  assert.equal(new URL(calls.resumed!.url).searchParams.get('state'), 'upstream-state');
  assert.equal(calls.resumed!.headers.get('Cookie'), 'upstream=yes');
  assert.deepEqual(calls.connection?.slice(1), ['private-token', 'America/Los_Angeles']);
  assert.deepEqual(calls.grant, {
    request: authRequest, userId: 'verified-user', metadata: {}, scope: OAUTH_SCOPES, props: { connectionId: 'connection-123' },
  });
  assert.equal((await response.text()).includes('private-token'), false);
});

test('upstream failures never return token-bearing error messages', async () => {
  const { env } = setup();
  const handler = createAuthHandler({
    getAppleSignInURL: async () => 'https://idmsa.apple.com/signin',
    connect: async () => { throw new Error('https://cloudkit.example?ckWebAuthToken=secret'); },
  });
  const response = await handler.fetch(new Request(`${origin}/callback`, {
    method: 'POST', headers: { Origin: origin }, body: JSON.stringify({ state: 'state', token: 'secret' }),
  }), env);
  assert.equal(response.status, 502);
  assert.equal((await response.text()).includes('secret'), false);
});

async function browserHarness() {
  const { handler, env } = setup();
  const script = await (await handler.fetch(new Request(`${origin}/auth.js`), env)).text();
  let click!: () => Promise<void>;
  let receive!: (event: unknown) => Promise<void>;
  let tick!: () => void;
  let expire!: () => void;
  let redirect = '';
  let reloaded = false;
  let removed = false;
  const requests: { path: string; options: RequestInit }[] = [];
  const popup = { close() { this.closed = true; }, location: '', closed: false };
  const status = { textContent: '' };
  const button = { disabled: false, addEventListener(_name: string, callback: typeof click) { click = callback; } };
  runInNewContext(script, {
    URL, Intl, JSON,
    setInterval(callback: typeof tick) { tick = callback; }, clearInterval() {},
    setTimeout(callback: typeof expire) { expire = callback; }, clearTimeout() {},
    document: { querySelector(selector: string) { return selector === '#allow' ? button : selector === '#status' ? status : {}; } },
    FormData: class { set() {} },
    window: {
      open: () => popup,
      addEventListener(_name: string, callback: typeof receive) { receive = callback; },
      removeEventListener() { removed = true; },
      location: { assign(value: string) { redirect = value; }, reload() { reloaded = true; } },
    },
    fetch: async (path: string, options: RequestInit) => {
      requests.push({ path, options });
      return { ok: true, json: async () => path === '/authorize' ? { state: 'bound-state', url: 'https://idmsa.apple.com/signin' } : { redirectTo: 'https://chatgpt.com/callback' } };
    },
  });
  return { click: () => click(), receive: (event: unknown) => receive(event), tick: () => tick(), expire: () => expire(),
    popup, status, button, requests, redirect: () => redirect, reloaded: () => reloaded, removed: () => removed };
}

test('popup bridge ignores forged messages and accepts only the opened Apple window', async () => {
  const { click, receive, popup, requests, redirect } = await browserHarness();
  await click();
  await receive({ source: {}, origin: 'https://idmsa.apple.com', data: { ckSession: 'forged' } });
  await receive({ source: popup, origin: 'https://apple.com.attacker.example', data: { ckSession: 'forged' } });
  assert.equal(requests.length, 1);
  await receive({ source: popup, origin: 'https://idmsa.apple.com', data: { ckSession: 'verified-token' } });
  assert.equal(requests.length, 2);
  assert.deepEqual(JSON.parse(String(requests[1].options.body)), { state: 'bound-state', token: 'verified-token' });
  assert.equal(redirect(), 'https://chatgpt.com/callback');
});

for (const reason of ['closed', 'error', 'expired']) {
  test(`a ${reason} Apple popup offers a fresh authorization instead of reusing consumed consent`, async () => {
    const browser = await browserHarness();
    await browser.click();
    if (reason === 'closed') {
      browser.popup.closed = true;
      browser.tick();
      browser.tick();
    } else if (reason === 'error') {
      await browser.receive({ source: browser.popup, origin: 'https://idmsa.apple.com', data: { errorMessage: 'cancelled' } });
    } else browser.expire();
    assert.equal(browser.button.disabled, false);
    assert.equal(browser.removed(), true);
    assert.equal(browser.requests.length, 1);
    await browser.click();
    assert.equal(browser.reloaded(), true);
    assert.equal(browser.requests.length, 1);
  });
}
