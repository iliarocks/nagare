import { CloudKitError } from './cloudkit.js';
import { NagareError } from './records.js';

// Only fixed vocabulary reaches retained logs. In particular, provider details,
// Error messages/stacks, request URLs, and upstream responses are never copied.
const oauthCodes = new Set([
  'invalid_request', 'invalid_client', 'invalid_grant', 'unauthorized_client',
  'unsupported_grant_type', 'unsupported_response_type', 'invalid_scope',
  'invalid_target', 'invalid_token', 'insufficient_scope', 'access_denied',
  'server_error', 'temporarily_unavailable',
]);
const oauthCategories = new Set([
  'client-authentication', 'authorization-code-grant', 'refresh-token-grant',
  'token-exchange-grant', 'token-endpoint-request', 'token-revocation',
  'token-issuance', 'resource-indicator', 'client-registration',
  'client-id-metadata-document', 'protected-resource',
  'enterprise-managed-authorization', 'token-exchange-callback',
]);
const oauthReasons = new Set([
  'method_not_allowed', 'unsupported_content_type', 'malformed_request_body',
  'repeated_parameter', 'multiple_authentication_methods', 'malformed_basic_credentials',
  'client_id_missing', 'client_not_found', 'token_endpoint_auth_method_mismatch',
  'client_secret_missing', 'client_secret_not_registered', 'client_secret_mismatch',
  'metadata_resolution_failed', 'grant_type_not_supported', 'grant_type_not_registered',
  'code_missing', 'code_malformed', 'grant_not_found', 'code_mismatch', 'client_mismatch',
  'code_replayed', 'pkce_method_invalid', 'redirect_uri_missing', 'redirect_uri_invalid',
  'redirect_uri_mismatch', 'unexpected_code_verifier', 'code_verifier_missing',
  'code_verifier_mismatch', 'scope_not_granted', 'refresh_token_ttl_invalid',
  'requested_ttl_too_short', 'refresh_token_missing', 'refresh_token_malformed',
  'refresh_token_mismatch', 'refresh_token_expired', 'refresh_token_idle_ttl_invalid',
  'token_missing', 'token_not_found', 'token_audience_unbound', 'token_expired',
  'audience_mismatch', 'kv_rate_limited', 'resource_invalid', 'resource_not_configured',
  'grant_audience_unbound', 'resource_grant_mismatch', 'legacy_grant_unbound',
  'legacy_grant_resource_mismatch', 'callback_error', 'callback_failed', 'callback_denied',
  'registration_disabled', 'metadata_invalid', 'public_client_forbidden',
  'declared_payload_too_large', 'payload_too_large', 'json_malformed',
]);
const cloudKitCodes = new Set([
  'AUTHENTICATION_REQUIRED', 'AUTHENTICATION_FAILED', 'ACCESS_DENIED', 'PERMISSION_FAILURE',
  'NETWORK_ERROR', 'AUTH_PERSIST_ERROR', 'THROTTLED', 'SERVICE_UNAVAILABLE',
  'INTERNAL_ERROR', 'HTTP_ERROR', 'UNEXPECTED_REDIRECT', 'UNEXPECTED_SERVER_RESPONSE',
  'CONFLICT', 'NOT_FOUND', 'UNKNOWN_ITEM', 'ALREADY_EXISTS', 'ZONE_NOT_FOUND',
  'QUOTA_EXCEEDED', 'LIMIT_EXCEEDED', 'TRANSACTION_TOO_LARGE', 'MISSING_RECORD_CHANGE_TAG',
  'READ_ONLY_ASSET', 'ASSET_TOO_LARGE', 'ASSET_SIZE_MISMATCH', 'INVALID_TEXT_ASSET',
  'INVALID_ASSET_URL', 'ASSET_HTTP_ERROR',
]);
const nagareCodes = new Set([
  'CONFLICT', 'EXTERNAL_TEXT', 'INVALID_ID', 'INVALID_MOVE', 'INVALID_RANGE',
  'INVALID_RECORD', 'INVALID_RECURRENCE', 'INVALID_SCHEDULE', 'INVALID_TITLE',
  'NOT_FOUND', 'SYNC_PENDING', 'TRANSACTION_TOO_LARGE',
]);
const signInStages = new Set(['consent', 'authorize', 'callback', 'complete']);
const signInOutcomes = new Set(['started', 'succeeded', 'failed']);
const credentialFailures = new Set(['missing_credentials', 'invalid_expiry', 'idle_expired']);
// Match only the provider's fixed descriptions; never retain message text.
const authorizationReasons = new Map([
  ['This authorization was not started in this browser; start again', 'browser_binding_missing'],
  ['This authorization belongs to a different browser session; start again', 'browser_binding_mismatch'],
  ['This authorization expired or was already used; start again', 'transaction_expired_or_used'],
  ['Please start the connection from your agent.', 'origin_rejected'],
]);
export type SignInStage = 'consent' | 'authorize' | 'callback' | 'complete';
export const browserSignInFailures = ['popup_blocked', 'popup_closed', 'popup_timeout', 'apple_error'] as const;
export type BrowserSignInFailure = typeof browserSignInFailures[number];
type CredentialFailure = 'missing_credentials' | 'invalid_expiry' | 'idle_expired';

function allowed(value: unknown, values: Set<string>): string {
  return typeof value === 'string' && values.has(value) ? value : 'other';
}

function httpStatus(value: unknown): { status?: number } {
  return typeof value === 'number' && Number.isInteger(value) && value >= 100 && value <= 599
    ? { status: value } : {};
}

function cloudKitFailure(error: CloudKitError) {
  const code = allowed(error.code, cloudKitCodes);
  const reason = code === 'AUTHENTICATION_REQUIRED' || code === 'AUTHENTICATION_FAILED'
    ? 'upstream_authentication' : code === 'NETWORK_ERROR'
      ? 'upstream_network' : code === 'AUTH_PERSIST_ERROR' ? 'credential_persistence' : 'upstream_failure';
  return { source: 'cloudkit', reason, code, ...httpStatus(error.status) };
}

export function logOAuthFailure(error: {
  code: string; status: number; internal?: { category?: string; reason?: string };
}): void {
  console.warn({ event: 'nagare_oauth_failure',
    code: allowed(error.code, oauthCodes), ...httpStatus(error.status),
    category: allowed(error.internal?.category, oauthCategories),
    reason: allowed(error.internal?.reason, oauthReasons),
  });
}

export function logSignInEvent(stage: SignInStage, outcome: 'started' | 'succeeded' | 'failed'): void {
  console.info({ event: 'nagare_sign_in', stage: allowed(stage, signInStages),
    outcome: allowed(outcome, signInOutcomes),
  });
}

export function logBrowserSignInFailure(reason: BrowserSignInFailure): void {
  console.warn({ event: 'nagare_sign_in_failure', source: 'browser',
    reason: allowed(reason, new Set(browserSignInFailures)),
  });
}

export function logAuthorizationFailure(error: unknown, stage: SignInStage = 'authorize'): void {
  const failure = error instanceof CloudKitError ? cloudKitFailure(error)
    : error instanceof Error && error.name === 'AuthorizationError' && 'code' in error
      ? { source: 'authorization',
        reason: error.code === 'invalid_request' && 'description' in error && typeof error.description === 'string'
          ? authorizationReasons.get(error.description) ?? 'authorization_rejected' : 'authorization_rejected',
        code: allowed(error.code, oauthCodes) }
      : { source: 'authorization', reason: 'unexpected_failure' };
  console.warn({ event: 'nagare_authorization_failure', stage: allowed(stage, signInStages), ...failure });
}

export function logCredentialFailure(reason: CredentialFailure): void {
  console.warn({ event: 'nagare_connection_failure', source: 'connection',
    reason: allowed(reason, credentialFailures),
  });
}

export function logToolFailure(error: unknown, storage = false): void {
  const failure = error instanceof CloudKitError ? cloudKitFailure(error)
    : error instanceof NagareError ? { source: 'nagare', reason: 'operation_rejected', code: allowed(error.code, nagareCodes) }
      : { source: storage ? 'connection' : 'tool', reason: storage ? 'credential_storage' : 'unexpected_failure' };
  console.warn({ event: 'nagare_tool_failure', ...failure });
}
