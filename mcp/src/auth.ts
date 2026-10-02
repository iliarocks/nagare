import {
  AuthorizationError,
  type ConsentDescription,
  type OAuthHelpers,
} from '@cloudflare/workers-oauth-provider';
import { CloudKitError } from './cloudkit.js';

export const OAUTH_SCOPES = ['nagare:read', 'nagare:write', 'offline_access'];
export type AuthProps = { connectionId: string };
export interface AuthEnvironment { OAUTH_PROVIDER: OAuthHelpers }

interface AppleConnection {
  connectionId: string;
  userId: string;
}

interface AuthDependencies<Env> {
  getAppleSignInURL(env: Env): Promise<string>;
  connect(env: Env, webAuthToken: string, timezone: string): Promise<AppleConnection>;
}

export function createAuthHandler<Env extends AuthEnvironment>(dependencies: AuthDependencies<Env>) {
  return {
    async fetch(request: Request, env: Env): Promise<Response> {
      const url = new URL(request.url);
      const oauth = env.OAUTH_PROVIDER;
      try {
        if (url.pathname === '/auth.js' && request.method === 'GET') {
          return new Response(browserScript, { headers: {
            'Content-Type': 'text/javascript; charset=utf-8', 'Cache-Control': 'no-store',
          } });
        }
        if (url.pathname === '/authorize' && request.method === 'GET') {
          const auth = await oauth.parseAuthRequest(request);
          const client = await oauth.describeConsent(auth);
          const consent = await oauth.beginConsent(auth);
          return page(consentPage(client, consent.handle), consent.headers);
        }
        if (url.pathname === '/authorize' && request.method === 'POST') {
          requireSameOrigin(request);
          const form = await request.formData();
          const handle = requiredString(form.get('handle'));
          if (form.get('decision') === 'deny') {
            const denied = await oauth.denyConsent(request, handle);
            return new Response(null, { status: 303, headers: denied.headers });
          }
          const timezone = requiredString(form.get('timezone'));
          // The connection keeps the user's calendar zone for all-day dates.
          new Intl.DateTimeFormat('en', { timeZone: timezone });
          const approved = await oauth.approveConsent(request, handle, { scope: OAUTH_SCOPES });
          const upstream = await oauth.beginUpstream(approved.request, {
            data: { timezone },
            headers: approved.headers,
          });
          const appleURL = new URL(await dependencies.getAppleSignInURL(env));
          if (!isAppleOrigin(appleURL.origin)) throw new Error('Unexpected Apple sign-in origin');
          return Response.json({ state: upstream.state, url: appleURL.href }, { headers: upstream.headers });
        }
        if (url.pathname === '/callback' && request.method === 'POST') {
          requireSameOrigin(request);
          const body = await request.json() as Record<string, unknown>;
          const state = requiredString(body.state);
          const token = requiredString(body.token);
          url.searchParams.set('state', state);
          const resumed = await oauth.finishUpstream<{ timezone: string }>(new Request(url, { headers: request.headers }));
          const connection = await dependencies.connect(env, token, resumed.data.timezone);
          const { redirectTo } = await oauth.completeAuthorization({
            request: resumed.request,
            userId: encodeURIComponent(connection.userId),
            metadata: {},
            scope: resumed.request.scope,
            props: { connectionId: connection.connectionId } satisfies AuthProps,
          });
          return Response.json({ redirectTo }, { headers: resumed.headers });
        }
        if (url.pathname === '/' && request.method === 'GET') {
          return page('<h1>Nagare</h1><p>Connect Nagare from your agent using this server’s <code>/mcp</code> endpoint.</p>');
        }
        return new Response('Not found', { status: 404 });
      } catch (error) {
        const expected = error instanceof AuthorizationError;
        if (!expected) console.error('Nagare connection failed', {
          code: error instanceof CloudKitError ? error.code : 'CONNECTION_ERROR',
        });
        const message = expected ? error.description : 'Connection failed. Return to your agent and try connecting again.';
        // Never return upstream errors: they can contain a CloudKit token or URL.
        if (request.method === 'POST') {
          return Response.json({ error: message }, { status: expected ? 400 : 502, headers: { 'Cache-Control': 'no-store' } });
        }
        return page(`<h1>Couldn’t connect</h1><p>${escapeHTML(message)}</p>`, undefined, expected ? 400 : 502);
      }
    },
  };
}

function requiredString(value: unknown): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > 16_384) {
    throw new AuthorizationError('invalid_request', { description: 'Missing or invalid connection details.' });
  }
  return value;
}

function requireSameOrigin(request: Request): void {
  if (request.headers.get('Origin') !== new URL(request.url).origin) {
    throw new AuthorizationError('invalid_request', { description: 'Please start the connection from your agent.' });
  }
}

function isAppleOrigin(origin: string): boolean {
  const url = new URL(origin);
  return url.protocol === 'https:' && ['apple.com', 'icloud.com', 'apple-cloudkit.com'].some(
    domain => url.hostname === domain || url.hostname.endsWith(`.${domain}`),
  );
}

function escapeHTML(value: string): string {
  return value.replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]!);
}

function consentPage(client: ConsentDescription, handle: string): string {
  return `<h1>Connect Nagare</h1>
    <p><strong>${escapeHTML(client.clientName)}</strong>${client.clientDomain ? ` (${escapeHTML(client.clientDomain)})` : ''} will be able to read and manage your tasks, projects, and repeats, including completing and deleting them.</p>
    <p>You can disconnect Nagare in your agent’s settings. Your Apple password stays with Apple.</p>
    <p class="detail">You’ll return to <strong>${escapeHTML(client.redirectHost)}</strong>.${client.redirectIsLoopback ? ' This is a local app; any process on your computer could receive this connection.' : ''}</p>
    <form id="connect" action="/authorize" method="post">
      <input type="hidden" name="handle" value="${escapeHTML(handle)}">
      <button id="allow" type="button">Connect with iCloud</button>
      <button class="secondary" name="decision" value="deny" type="submit">Cancel</button>
    </form><p id="status" role="status"></p><script src="/auth.js" defer></script>`;
}

function page(content: string, headers = new Headers(), status = 200): Response {
  headers.set('Content-Type', 'text/html; charset=utf-8');
  headers.set('Cache-Control', 'no-store');
  headers.set('Referrer-Policy', 'no-referrer');
  headers.set('X-Frame-Options', 'DENY');
  headers.set('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'");
  return new Response(`<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Connect Nagare</title><style>
    :root {
      color-scheme: light dark;
      --accent: #607d8b;
      --background: #f7f8fa;
      --surface: #ffffff;
      --text: #151719;
      --secondary: #676c70;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100svh;
      display: grid;
      align-items: center;
      background: var(--background);
      color: var(--text);
      font: 17px/1.55 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
      -webkit-font-smoothing: antialiased;
    }
    main { width: min(480px, calc(100% - 48px)); margin-inline: auto; padding-block: 64px; }
    h1 { margin: 0 0 32px; font-size: clamp(3rem, 9vw, 3.7rem); line-height: 1.02; letter-spacing: -.055em; font-weight: 730; }
    p { margin: 20px 0; color: var(--secondary); overflow-wrap: anywhere; }
    strong { color: var(--text); font-weight: 650; }
    .detail, #status { font-size: .875rem; }
    form { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 32px; }
    button {
      min-height: 54px;
      padding: 13px 24px;
      border: 0;
      border-radius: 999px;
      background: var(--text);
      color: var(--surface);
      font: inherit;
      font-weight: 650;
      cursor: pointer;
    }
    button:hover { opacity: .88; }
    button:focus-visible { outline: 3px solid var(--accent); outline-offset: 4px; }
    button:disabled { opacity: .5; cursor: wait; }
    .secondary { background: transparent; color: var(--secondary); }
    #status { min-height: 1.55em; margin-bottom: 0; }
    @media (prefers-color-scheme: dark) {
      :root { --accent: #86a3b3; --background: #080808; --surface: #1c1c1c; --text: #f5f5f5; --secondary: #b0b0b0; }
    }
    </style></head><body><main>${content}</main></body></html>`, { status, headers });
}

// CloudKit's popup response has no OAuth state. Keep the state in this page and
// accept the token only from the Apple popup we opened, then post it same-origin.
const browserScript = `
const form = document.querySelector('#connect');
const button = document.querySelector('#allow');
const status = document.querySelector('#status');
let retry = false;
button.addEventListener('click', async () => {
  if (retry) { window.location.reload(); return; }
  const popup = window.open('about:blank', '_blank', 'popup,width=640,height=640');
  if (!popup) { status.textContent = 'Allow pop-ups to sign in with iCloud.'; return; }
  button.disabled = true;
  let state;
  let received = false;
  let closedOnce = false;
  let timeout;
  let closed;
  const cleanup = () => {
    window.removeEventListener('message', receive);
    clearTimeout(timeout);
    clearInterval(closed);
  };
  const fail = message => {
    if (retry) return;
    cleanup();
    popup.close();
    status.textContent = message;
    button.disabled = false;
    button.textContent = 'Try again';
    retry = true;
  };
  const receive = async event => {
    if (received || !state || event.source !== popup) return;
    let origin;
    try { origin = new URL(event.origin); } catch { return; }
    if (origin.protocol !== 'https:' || !['apple.com', 'icloud.com', 'apple-cloudkit.com'].some(domain => origin.hostname === domain || origin.hostname.endsWith('.' + domain))) return;
    if (event.data?.errorMessage) { fail('Apple sign-in didn’t complete. Please try again.'); return; }
    const token = event.data?.ckSession ?? event.data?.ckWebAuthToken;
    if (typeof token !== 'string' || !token) return;
    received = true;
    cleanup();
    popup.close();
    status.textContent = 'Connecting…';
    try {
      const response = await fetch('/callback', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ state, token }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      window.location.assign(result.redirectTo);
    } catch (error) { fail(error.message); }
  };
  window.addEventListener('message', receive);
  // Give Apple's final postMessage time to arrive after its window closes.
  closed = setInterval(() => {
    if (!popup.closed) return;
    if (closedOnce) fail('Sign-in was cancelled. You can try again.');
    closedOnce = true;
  }, 500);
  timeout = setTimeout(() => fail('This connection expired. Please try again.'), 600000);
  try {
    const body = new FormData(form);
    body.set('timezone', Intl.DateTimeFormat().resolvedOptions().timeZone);
    const response = await fetch('/authorize', { method: 'POST', body });
    const result = await response.json();
    if (retry) return;
    if (!response.ok) throw new Error(result.error);
    state = result.state;
    popup.location = result.url;
    status.textContent = 'Finish signing in with Apple in the pop-up window.';
  } catch (error) {
    fail(error.message);
  }
});
`;
