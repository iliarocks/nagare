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
const { getOAuthApi } = await import('@cloudflare/workers-oauth-provider');

const origin = 'https://mcp.development.nagare.page';
const authRequest = { clientId: 'client', redirectUri: 'https://chatgpt.com/callback', scope: OAUTH_SCOPES } as AuthRequest;
const client: ConsentDescription = {
  clientId: 'client', clientName: 'ChatGPT', redirectUri: authRequest.redirectUri,
  redirectHost: 'chatgpt.com', redirectIsLoopback: false, scope: OAUTH_SCOPES,
};

function setup(overrides: Partial<OAuthHelpers> = {}) {
  const calls: { connection?: unknown[]; grant?: unknown; resumed?: Request; denied?: unknown[] } = {};
  const oauth = {
    parseAuthRequest: async () => authRequest,
    describeConsent: async () => client,
    beginConsent: async () => ({ handle: 'consent', headers: new Headers({ 'Set-Cookie': 'binding=yes' }) }),
    denyConsent: async (...args: unknown[]) => {
      calls.denied = args;
      return { request: authRequest, redirectTo: authRequest.redirectUri,
        headers: new Headers({ 'Location': authRequest.redirectUri, 'Set-Cookie': 'binding=; Max-Age=0' }) };
    },
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

test('a blocked popup report consumes consent without granting access or redirecting', async () => {
  const { handler, env, calls } = setup();
  const response = await handler.fetch(new Request(`${origin}/authorize`, {
    method: 'POST', headers: { Origin: origin, Cookie: 'binding=yes' },
    body: new URLSearchParams({ handle: 'consent', decision: 'popup_blocked' }),
  }), env);
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Location'), null);
  assert.equal(response.headers.get('Set-Cookie'), 'binding=; Max-Age=0');
  assert.equal((calls.denied?.[0] as Request).headers.get('Cookie'), 'binding=yes');
  assert.equal(calls.denied?.[1], 'consent');
  assert.equal(calls.connection, undefined);
  assert.equal(calls.grant, undefined);
});

test('foreign-origin blocked popup reports cannot consume consent', async () => {
  const { handler, env, calls } = setup();
  const response = await handler.fetch(new Request(`${origin}/authorize`, {
    method: 'POST', headers: { Origin: 'https://attacker.example' },
    body: new URLSearchParams({ handle: 'consent', decision: 'popup_blocked' }),
  }), env);
  assert.equal(response.status, 400);
  assert.equal(calls.denied, undefined);
});

test('failure callbacks reject unrecognized reports before consuming state', async () => {
  for (const error of ['Apple says secret-token', '', null, { code: 'popup_closed' }]) {
    const { handler, env, calls } = setup();
    const response = await handler.fetch(new Request(`${origin}/callback`, {
      method: 'POST', headers: { Origin: origin }, body: JSON.stringify({ state: 'state', error }),
    }), env);
    assert.equal(response.status, 400);
    assert.equal(calls.resumed, undefined);
    assert.equal(calls.connection, undefined);
    assert.equal((await response.text()).includes('secret-token'), false);
  }
});

test('failure callbacks use real browser-bound, single-use upstream transactions', async () => {
  // Use the production OAuth library for the binding and replay checks. The
  // in-memory KV only replaces persistence; it does not reimplement validation.
  const stored = new Map<string, string>();
  const oauth = getOAuthApi({
    apiRoute: '/', apiHandler: { fetch: () => new Response() },
    defaultHandler: { fetch: () => new Response() },
    authorizeEndpoint: `${origin}/authorize`, tokenEndpoint: `${origin}/oauth/token`,
    scopesSupported: OAUTH_SCOPES,
    resourceMetadata: { resource: origin, authorization_servers: [origin] },
  }, { OAUTH_KV: {
    get: async (key: string) => stored.get(key) ?? null,
    put: async (key: string, value: string) => { stored.set(key, value); },
    delete: async (key: string) => { stored.delete(key); },
  } as unknown as KVNamespace });
  const upstream = await oauth.beginUpstream(authRequest, { data: { timezone: 'America/Los_Angeles' } });
  const cookie = upstream.headers.get('Set-Cookie')!.split(';')[0];
  const { handler, env, calls } = setup({ finishUpstream: request => oauth.finishUpstream(request) });
  const callback = (state: string | undefined, cookies?: string, token?: string) => handler.fetch(new Request(`${origin}/callback`, {
    method: 'POST', headers: { Origin: origin, ...(cookies ? { Cookie: cookies } : {}) },
    body: JSON.stringify({ state, ...(token ? { token } : { error: 'popup_closed' }) }),
  }), env);
  assert.equal((await callback(undefined, cookie)).status, 400);
  assert.equal((await callback(upstream.state)).status, 400);
  assert.equal((await callback('attacker-state', cookie)).status, 400);
  // A token-bearing top-level navigation must not create an authenticated link.
  const injected = await handler.fetch(new Request(`${origin}/callback?ckWebAuthToken=attacker-token`, {
    headers: { Cookie: cookie },
  }), env);
  assert.equal(injected.status, 404);
  const accepted = await callback(upstream.state, cookie);
  assert.equal(accepted.status, 204);
  assert.match(accepted.headers.get('Set-Cookie')!, /Max-Age=0/);
  assert.equal((await callback(upstream.state, cookie)).status, 400);
  assert.equal((await callback(upstream.state, cookie, 'attacker-token')).status, 400);
  assert.equal(calls.connection, undefined);
  assert.equal(calls.grant, undefined);
});

interface BrowserResponse {
  ok: boolean;
  json(): Promise<Record<string, unknown>>;
}
type BrowserRequestInit = RequestInit & { keepalive?: boolean };

async function browserHarness(options: {
  open?: 'blocked' | 'throws'; closeThrows?: boolean; reportFails?: boolean;
  authorize?: () => Promise<BrowserResponse>;
} = {}) {
  const { handler, env } = setup();
  const script = await (await handler.fetch(new Request(`${origin}/auth.js`), env)).text();
  let click!: () => Promise<void>;
  let receive: ((event: unknown) => Promise<void>) | undefined;
  let now = 1_700_000_000_000;
  let nextTimer = 1;
  const timers = new Map<number, { callback: () => void; when: number; interval?: number }>();
  let redirect = '';
  let reloaded = false;
  let removed = false;
  const requests: { path: string; options: BrowserRequestInit }[] = [];
  const popup = { close() { if (options.closeThrows) throw new Error('Window unavailable'); this.closed = true; }, location: '', closed: false };
  const status = { textContent: '' };
  const button = { disabled: false, textContent: 'Connect with iCloud', addEventListener(_name: string, callback: typeof click) { click = callback; } };
  const addTimer = (callback: () => void, delay: number, interval?: number) => {
    const id = nextTimer++;
    timers.set(id, { callback, when: now + delay, interval });
    return id;
  };
  runInNewContext(script, {
    URL, Intl, JSON,
    Date: class extends Date { static now() { return now; } },
    setInterval: (callback: () => void, delay: number) => addTimer(callback, delay, delay),
    setTimeout: (callback: () => void, delay: number) => addTimer(callback, delay),
    clearInterval: (id: number) => timers.delete(id), clearTimeout: (id: number) => timers.delete(id),
    document: { querySelector(selector: string) { return selector === '#allow' ? button : selector === '#status' ? status : {}; } },
    FormData: class extends Map<string, string> { constructor() { super([['handle', 'consent']]); } },
    window: {
      open: () => { if (options.open === 'throws') throw new Error('Popup blocked'); return options.open === 'blocked' ? null : popup; },
      addEventListener(_name: string, callback: typeof receive) { receive = callback; },
      removeEventListener() { removed = true; receive = undefined; },
      location: { assign(value: string) { redirect = value; }, reload() { reloaded = true; } },
    },
    fetch: async (path: string, requestOptions: BrowserRequestInit) => {
      requests.push({ path, options: requestOptions });
      if (path === '/authorize' && requestOptions.body instanceof Map && requestOptions.body.get('decision') !== 'popup_blocked') {
        return authorize();
      }
      if (requestOptions.keepalive && reportFails) throw new Error('Report network error');
      return { ok: true, json: async () => ({ redirectTo: 'https://chatgpt.com/callback' }) };
    },
  });
  const authorize = options.authorize ?? (async () => ({ ok: true, json: async () => ({ state: 'bound-state', url: 'https://idmsa.apple.com/signin' }) }));
  const reportFails = options.reportFails;
  const advance = (milliseconds: number) => {
    const until = now + milliseconds;
    for (;;) {
      const due = [...timers].filter(([, timer]) => timer.when <= until).sort((a, b) => a[1].when - b[1].when)[0];
      if (!due) break;
      const [id, timer] = due;
      now = timer.when;
      if (timer.interval) timer.when += timer.interval;
      else timers.delete(id);
      timer.callback();
    }
    now = until;
  };
  return { click: () => click(), receive: async (event: unknown) => receive?.(event), advance,
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

for (const [reason, expectedReport] of [['closed', 'popup_closed'], ['error', 'apple_error'], ['expired', 'popup_timeout']]) {
  test(`a ${reason} Apple popup offers a fresh authorization instead of reusing consumed consent`, async () => {
    const browser = await browserHarness();
    await browser.click();
    if (reason === 'closed') {
      browser.popup.closed = true;
      browser.advance(3500);
    } else if (reason === 'error') {
      await browser.receive({ source: browser.popup, origin: 'https://idmsa.apple.com', data: { errorMessage: 'cancelled with secret-token', ckSession: 'secret-token' } });
    } else browser.advance(600000);
    assert.equal(browser.button.disabled, false);
    assert.equal(browser.removed(), true);
    assert.equal(browser.requests.length, 2);
    assert.deepEqual(JSON.parse(String(browser.requests[1].options.body)), { state: 'bound-state', error: expectedReport });
    assert.equal(browser.requests[1].options.keepalive, true);
    assert.equal(browser.status.textContent.includes('secret-token'), false);
    await browser.click();
    assert.equal(browser.reloaded(), true);
    assert.equal(browser.requests.length, 2);
  });
}

for (const open of ['blocked', 'throws'] as const) {
  test(`a ${open} popup reports only the bound consent and offers a new attempt`, async () => {
    const browser = await browserHarness({ open });
    await browser.click();
    assert.equal(browser.requests.length, 1);
    assert.equal(browser.requests[0].path, '/authorize');
    assert.deepEqual([...browser.requests[0].options.body as unknown as Map<string, string>], [
      ['handle', 'consent'], ['decision', 'popup_blocked'],
    ]);
    assert.equal(browser.requests[0].options.keepalive, true);
    assert.equal(browser.button.disabled, false);
    assert.match(browser.status.textContent, /Allow pop-ups/);
    await browser.click();
    assert.equal(browser.reloaded(), true);
    assert.equal(browser.requests.length, 1);
  });
}

test('an Apple result delivered after the popup closes can still finish authentication', async () => {
  const browser = await browserHarness({ closeThrows: true });
  await browser.click();
  browser.popup.closed = true;
  browser.advance(3000);
  assert.equal(browser.button.disabled, true);
  await browser.receive({ source: {}, origin: 'https://idmsa.apple.com', data: { ckSession: 'forged' } });
  assert.equal(browser.requests.length, 1);
  await browser.receive({ source: browser.popup, origin: 'https://idmsa.apple.com', data: { ckWebAuthToken: 'verified-token' } });
  assert.equal(browser.redirect(), 'https://chatgpt.com/callback');
  assert.deepEqual(JSON.parse(String(browser.requests[1].options.body)), { state: 'bound-state', token: 'verified-token' });
  browser.advance(600000);
  assert.equal(browser.requests.length, 2);
});

test('a popup closed while authorization is pending reports once when the bound state arrives', async () => {
  let resolve!: (response: BrowserResponse) => void;
  const response = new Promise<BrowserResponse>(done => { resolve = done; });
  const browser = await browserHarness({ authorize: () => response, reportFails: true, closeThrows: true });
  const clicking = browser.click();
  browser.popup.closed = true;
  browser.advance(3500);
  assert.equal(browser.requests.length, 1);
  assert.equal(browser.button.disabled, false);
  resolve({ ok: true, json: async () => ({ state: 'late-bound-state', url: 'https://idmsa.apple.com/signin' }) });
  await clicking;
  assert.equal(browser.requests.length, 2);
  assert.deepEqual(JSON.parse(String(browser.requests[1].options.body)), { state: 'late-bound-state', error: 'popup_closed' });
  assert.equal(browser.popup.location, '');
  assert.equal(browser.redirect(), '');
  browser.advance(600000);
  await browser.click();
  assert.equal(browser.reloaded(), true);
  assert.equal(browser.requests.length, 2);
});

test('a rejected authorization request restores a retry without fabricating a browser report', async () => {
  const browser = await browserHarness({ authorize: async () => ({ ok: false, json: async () => ({ error: 'Please reconnect.' }) }) });
  await browser.click();
  assert.equal(browser.requests.length, 1);
  assert.equal(browser.button.disabled, false);
  assert.equal(browser.status.textContent, 'Please reconnect.');
  assert.equal(browser.removed(), true);
  await browser.click();
  assert.equal(browser.reloaded(), true);
});
