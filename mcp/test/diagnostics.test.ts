import assert from 'node:assert/strict';
import test from 'node:test';
import { CloudKitError } from '../src/cloudkit.js';
import {
  logAuthorizationFailure, logCredentialFailure, logOAuthFailure, logSignInEvent, logToolFailure,
  type SignInStage,
} from '../src/diagnostics.js';

const secret = 'private-token-task-title-user-id';

test('OAuth diagnostics retain stable reasons without provider details or request credentials', t => {
  const warn = t.mock.method(console, 'warn', () => {});
  const error = {
    code: 'invalid_grant', status: 400, description: secret,
    headers: { Authorization: `Bearer ${secret}` },
    request: new Request(`https://example.test/token?secret=${secret}`),
    internal: { category: 'refresh-token-grant', reason: 'refresh_token_mismatch',
      detail: { token: secret, userId: secret, error: new Error(secret) } },
  };
  logOAuthFailure(error);
  assert.deepEqual(warn.mock.calls[0].arguments, [{
    event: 'nagare_oauth_failure', code: 'invalid_grant', status: 400,
    category: 'refresh-token-grant', reason: 'refresh_token_mismatch',
  }]);
  logOAuthFailure({ code: secret, status: NaN, internal: { category: secret, reason: secret } });
  assert.deepEqual(warn.mock.calls[1].arguments, [{
    event: 'nagare_oauth_failure', code: 'other', category: 'other', reason: 'other',
  }]);
  assert.equal(JSON.stringify(warn.mock.calls.map(call => call.arguments)).includes(secret), false);
});

test('sign-in stages distinguish handoff, callback receipt, and completion without identifiers', t => {
  const info = t.mock.method(console, 'info', () => {});
  logSignInEvent('authorize', 'succeeded');
  logSignInEvent('callback', 'started');
  logSignInEvent('complete', 'succeeded');
  assert.deepEqual(info.mock.calls.map(call => call.arguments[0]), [
    { event: 'nagare_sign_in', stage: 'authorize', outcome: 'succeeded' },
    { event: 'nagare_sign_in', stage: 'callback', outcome: 'started' },
    { event: 'nagare_sign_in', stage: 'complete', outcome: 'succeeded' },
  ]);
  logSignInEvent(secret as SignInStage, secret as 'failed');
  assert.deepEqual(info.mock.calls[3].arguments, [{ event: 'nagare_sign_in', stage: 'other', outcome: 'other' }]);
});

test('authorization failures retain provenance while excluding upstream identities and arbitrary errors', t => {
  const warn = t.mock.method(console, 'warn', () => {});
  logAuthorizationFailure(new CloudKitError('AUTHENTICATION_REQUIRED', 401, [{
    serverErrorCode: secret, recordName: secret, redirectURL: `https://apple.example?token=${secret}`,
  }]), 'callback');
  const denied = Object.assign(new Error(secret), { name: 'AuthorizationError', code: 'invalid_request' });
  logAuthorizationFailure(denied, 'consent');
  logAuthorizationFailure(new Error(secret), 'complete');
  logAuthorizationFailure(new CloudKitError(secret, 123456, []));
  assert.deepEqual(warn.mock.calls.map(call => call.arguments[0]), [
    { event: 'nagare_authorization_failure', stage: 'callback', source: 'cloudkit',
      reason: 'upstream_authentication', code: 'AUTHENTICATION_REQUIRED', status: 401 },
    { event: 'nagare_authorization_failure', stage: 'consent', source: 'authorization',
      reason: 'authorization_rejected', code: 'invalid_request' },
    { event: 'nagare_authorization_failure', stage: 'complete', source: 'authorization', reason: 'unexpected_failure' },
    { event: 'nagare_authorization_failure', stage: 'authorize', source: 'cloudkit', reason: 'upstream_failure', code: 'other' },
  ]);
  assert.equal(JSON.stringify(warn.mock.calls.map(call => call.arguments)).includes(secret), false);
});

test('local credential and unexpected tool failures never serialize unknown data', t => {
  const warn = t.mock.method(console, 'warn', () => {});
  logCredentialFailure('missing_credentials');
  logToolFailure({ task: secret, message: secret });
  logToolFailure(new Error(secret), true);
  assert.deepEqual(warn.mock.calls.map(call => call.arguments[0]), [
    { event: 'nagare_connection_failure', source: 'connection', reason: 'missing_credentials' },
    { event: 'nagare_tool_failure', source: 'tool', reason: 'unexpected_failure' },
    { event: 'nagare_tool_failure', source: 'connection', reason: 'credential_storage' },
  ]);
});

test('authorization diagnostics distinguish browser binding, expired state, and origin rejection without messages', t => {
  const warn = t.mock.method(console, 'warn', () => {});
  const cases = [
    ['This authorization was not started in this browser; start again', 'browser_binding_missing'],
    ['This authorization belongs to a different browser session; start again', 'browser_binding_mismatch'],
    ['This authorization expired or was already used; start again', 'transaction_expired_or_used'],
    ['Please start the connection from your agent.', 'origin_rejected'],
    [`This authorization expired or was already used; start again ${secret}`, 'authorization_rejected'],
    [secret, 'authorization_rejected'],
  ];
  for (const [description] of cases) {
    logAuthorizationFailure(Object.assign(new Error(description), {
      name: 'AuthorizationError', code: 'invalid_request', description,
      state: secret, redirectUri: `https://client.example/${secret}`,
    }), 'callback');
  }
  assert.deepEqual(warn.mock.calls.map(call => call.arguments[0]), cases.map(([, reason]) => ({
    event: 'nagare_authorization_failure', stage: 'callback', source: 'authorization',
    code: 'invalid_request', reason,
  })));
  const serialized = JSON.stringify(warn.mock.calls.map(call => call.arguments));
  assert.equal(serialized.includes(secret), false);
  for (const [description] of cases) assert.equal(serialized.includes(description), false);
});
