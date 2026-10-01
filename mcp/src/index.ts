import OAuthProvider, { insufficientScope, type OAuthResourceAuth } from '@cloudflare/workers-oauth-provider';
import { McpServer } from '@modelcontextprotocol/server';
import { createMcpHandler } from 'agents/mcp/server';
import { z } from 'zod';
import { createAuthHandler, OAUTH_SCOPES, type AuthProps } from './auth.js';
import { CloudKitError } from './cloudkit.js';
import { cloudKit, ORIGIN, type Env, type Operation } from './connection.js';

export { Connection } from './connection.js';

const requiredScopes = ['nagare:read', 'nagare:write'];
const schedule = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe('Calendar date in the user’s connected time zone.'),
  time: z.string().nullable().optional().describe('Local HH:mm. Null makes the task all-day; omitted preserves existing timing.'),
  endTime: z.string().nullable().optional().describe('Local HH:mm after the start, or null to remove the end time.'),
});
const changes = z.object({
  title: z.string().max(10_000).optional(),
  notes: z.string().max(100_000).nullable().optional(),
  schedule: schedule.optional(),
  projectId: z.uuid().nullable().optional().describe('Project ID, or null to remove the project.'),
});

function createServer(env: Env, connectionId: string) {
  const server = new McpServer({ name: 'Nagare Development', version: '0.1.0' });
  const connection = env.CONNECTIONS.get(env.CONNECTIONS.idFromName(connectionId));
  const invoke = async (operation: Operation) => {
    const result = await connection.run(operation);
    if (!result.ok) {
      return {
        isError: true,
        content: [{ type: 'text' as const, text: `${result.code}: ${result.message}` }],
        ...(['AUTHENTICATION_REQUIRED', 'AUTHENTICATION_FAILED'].includes(result.code) ? {
          _meta: { 'mcp/www_authenticate': [`Bearer resource_metadata="${ORIGIN}/.well-known/oauth-protected-resource/mcp", error="invalid_token", error_description="Reconnect Nagare with iCloud"`] },
        } : {}),
      };
    }
    return { content: [{ type: 'text' as const, text: JSON.stringify(result.data) }] };
  };
  const securitySchemes = [{ type: 'oauth2', scopes: requiredScopes }];
  const read = { readOnlyHint: true, destructiveHint: false, openWorldHint: false };
  const write = { readOnlyHint: false, destructiveHint: false, openWorldHint: false, idempotentHint: true };
  server.registerTool('list_projects', {
    description: 'List Nagare projects, including priority and notes.',
    inputSchema: {}, annotations: read, _meta: { securitySchemes },
  }, () => invoke({ name: 'list_projects' }));
  server.registerTool('list_tasks', {
    description: 'Read saved Nagare tasks and their revisions. Includes realized recurring tasks, but not projected future occurrences. Use before editing; dates use the connected user’s time zone.',
    inputSchema: { completed: z.boolean().optional(), projectId: z.uuid().optional(), date: z.string().optional() },
    annotations: read, _meta: { securitySchemes },
  }, options => invoke({ name: 'list_tasks', options }));
  server.registerTool('create_task', {
    description: 'Create an ordinary Nagare task. Generate a UUID for id and reuse that exact id on retries to avoid duplicates. Cannot create repeating tasks.',
    inputSchema: {
      id: z.uuid(), title: z.string().max(10_000), notes: z.string().max(100_000).nullable().optional(),
      projectId: z.uuid().nullable().optional(), schedule,
    },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'create_task', input }));
  server.registerTool('update_task', {
    description: 'Edit or reschedule an ordinary task. Supply its latest revision from list_tasks and only fields the user wants changed. Repeating tasks are not editable in this prototype.',
    inputSchema: { id: z.uuid(), revision: z.string().min(1), changes },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'update_task', ...input }));
  server.registerTool('complete_task', {
    description: 'Complete an ordinary task using its latest revision from list_tasks. Repeating tasks are not editable in this prototype.',
    inputSchema: { id: z.uuid(), revision: z.string().min(1) },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'complete_task', ...input }));
  return server;
}

export default new OAuthProvider<Env>({
  apiRoute: '/mcp',
  apiHandler: {
    async fetch(request, env, ctx) {
      const { props, auth } = ctx as typeof ctx & { props: AuthProps; auth: OAuthResourceAuth };
      if (!requiredScopes.every(scope => auth.scope.includes(scope))) return insufficientScope(auth, requiredScopes);
      if (!props.connectionId) return new Response('Invalid connection', { status: 401 });
      return createMcpHandler(() => createServer(env, props.connectionId), {
        allowedHostnames: [new URL(ORIGIN).hostname],
        allowedOriginHostnames: [new URL(ORIGIN).hostname],
      })(request, env, ctx);
    },
  },
  defaultHandler: createAuthHandler<Env>({
    async getAppleSignInURL(env) {
      try { await cloudKit(env).currentUser(); }
      catch (error) {
        if (error instanceof CloudKitError && error.code === 'AUTHENTICATION_REQUIRED' && error.redirectURL) return error.redirectURL;
        throw error;
      }
      throw new Error('Apple did not return a sign-in URL.');
    },
    async connect(env, webAuthToken, timezone) {
      const client = cloudKit(env, webAuthToken, async token => { webAuthToken = token; });
      const user = await client.currentUser();
      const identity = `${env.CLOUDKIT_CONTAINER}:${env.CLOUDKIT_ENVIRONMENT}:${user.userRecordName}`;
      const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(identity));
      const connectionId = Array.from(new Uint8Array(hash), byte => byte.toString(16).padStart(2, '0')).join('');
      await env.CONNECTIONS.get(env.CONNECTIONS.idFromName(connectionId)).configure(webAuthToken, timezone);
      return { connectionId, userId: connectionId };
    },
  }),
  authorizeEndpoint: '/authorize',
  tokenEndpoint: '/oauth/token',
  clientRegistrationEndpoint: '/oauth/register',
  clientIdMetadataDocumentEnabled: true,
  refreshTokenIdleTTL: 30 * 24 * 60 * 60,
  scopesSupported: OAUTH_SCOPES,
  requiredScopes,
  resourceMetadata: { resource: `${ORIGIN}/mcp`, authorization_servers: [ORIGIN], resource_name: 'Nagare Development' },
});
