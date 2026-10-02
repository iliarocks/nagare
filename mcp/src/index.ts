import OAuthProvider, { insufficientScope, type OAuthResourceAuth } from '@cloudflare/workers-oauth-provider';
import { McpServer } from '@modelcontextprotocol/server';
import { createMcpHandler } from 'agents/mcp/server';
import { z } from 'zod';
import { createAuthHandler, OAUTH_SCOPES, type AuthProps } from './auth.js';
import { CloudKitError } from './cloudkit.js';
import { cloudKit, ORIGIN, type Env, type Operation } from './connection.js';

export { Connection } from './connection.js';

const requiredScopes = ['nagare:read', 'nagare:write'];
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).describe('Calendar date, YYYY-MM-DD.');
const time = z.string().regex(/^(?:[01]\d|2[0-3]):[0-5]\d$/).describe('Time, HH:mm.');
const revision = z.string().min(1).describe('Latest revision returned when reading this item.');
const revisions = z.record(z.uuid(), revision).describe('Latest revisions keyed by item ID. Include every selected item.');
const projectId = z.uuid().nullable().describe('Project ID, or null for no project.');
const schedule = z.object({
  date,
  time: time.nullable().optional().describe('HH:mm, or null for a task without a time. Omitted preserves existing timing.'),
  endTime: time.nullable().optional().describe('HH:mm after the start, or null to remove the end time.'),
});
const textChanges = {
  title: z.string().min(1).optional(),
  notes: z.string().nullable().optional(),
};
const projectChanges = z.object({ ...textChanges, prioritized: z.boolean().optional() });
const rule = z.object({
  mode: z.enum(['relative', 'absolute']).describe('Relative repeats advance by an interval; absolute repeats follow a calendar pattern.'),
  unit: z.enum(['day', 'week', 'month', 'year']),
  interval: z.number().int().positive(),
  anchors: z.array(z.number().int().min(0).max(30)).optional().describe('Absolute weekly: 0=Monday through 6=Sunday. Absolute monthly: 0=first day through 30=31st. Omit for other rules.'),
  reference: date.nullable().optional().describe('Required for absolute repeats; establishes the calendar pattern.'),
  repeatUntil: date.nullable().optional().describe('Last permitted occurrence date, inclusive. Null means no end date.'),
});
const taskChanges = z.object({
  ...textChanges,
  schedule: schedule.optional(),
  projectId: projectId.optional(),
  recurrence: rule.nullable().optional().describe('Set or replace the repeat rule, or null to stop repeating. Omitted preserves the rule.'),
});
const filters = {
  from: date.optional().describe('First included date.'),
  through: date.optional().describe('Last included date.'),
  projectId: projectId.optional(),
  query: z.string().optional().describe('Search titles and notes.'),
};
const taskMove = z.object({
  ids: z.array(z.uuid()).min(1).describe('Task IDs in the desired block order.'),
  beforeId: z.uuid().nullable().optional().describe('Insert before this task; omit or use null to append.'),
  date: date.optional().describe('Reorder the daily task list for this date.'),
  projectId: z.uuid().optional().describe('Reorder the task list within this project.'),
  revisions,
}).refine(input => (input.date !== undefined) !== (input.projectId !== undefined), {
  message: 'Choose exactly one list context: date or projectId.',
});

function createServer(env: Env, connectionId: string) {
  const server = new McpServer({ name: 'Nagare Development', version: '0.2.0' }, {
    instructions: 'Ordinary task queries return active tasks, including projected repeats. Completed history is queried separately. Preserve the provided order unless the user asks to organize tasks differently. For a normal task list, show titles and times when present; omit routine labels such as ‘incomplete’ or ‘anytime.’ Add notes, project context, or other details when they help answer the request.',
  });
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
  const destructive = { ...write, destructiveHint: true };
  server.registerTool('list_projects', {
    description: 'List projects in their native order, with titles, notes, priority, and editable revisions.',
    inputSchema: {}, annotations: read, _meta: { securitySchemes },
  }, () => invoke({ name: 'list_projects' }));
  server.registerTool('create_project', {
    description: 'Create a project at the end of its priority group. Generate a UUID for id and reuse it on retries to avoid duplicates.',
    inputSchema: { id: z.uuid(), title: z.string().min(1), notes: z.string().nullable().optional(), prioritized: z.boolean().optional() },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'create_project', input }));
  server.registerTool('update_project', {
    description: 'Edit a project using its latest revision. Supply only changed fields. Prioritizing moves it to the end of the prioritized group; removing priority moves it to the start of the normal group.',
    inputSchema: { id: z.uuid(), revision, changes: projectChanges },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'update_project', ...input }));
  server.registerTool('delete_project', {
    description: 'Delete a project using its latest revision. Its tasks and recurrence rules are retained without a project.',
    inputSchema: { id: z.uuid(), revision },
    annotations: destructive, _meta: { securitySchemes },
  }, input => invoke({ name: 'delete_project', ...input }));
  server.registerTool('reorder_projects', {
    description: 'Move projects as a block within a priority group. Use prioritized to choose the destination group, or inherit it from beforeId. Without either, selected projects must share a priority group.',
    inputSchema: {
      ids: z.array(z.uuid()).min(1).describe('Project IDs in the desired block order.'),
      beforeId: z.uuid().nullable().optional().describe('Insert before this project; omit or use null to append.'),
      prioritized: z.boolean().optional(), revisions,
    },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'reorder_projects', input }));
  server.registerTool('list_tasks', {
    description: 'List active tasks and projected recurring occurrences. Today includes overdue tasks. Calendar projections extend through the requested end date, or two months by default; relative repeats show their next occurrence. Saved tasks include editable revisions. Projected occurrences have compound IDs and are read-only; use their recurrence ID to edit future occurrences. Use list_completed_tasks for completed history.',
    inputSchema: { date: z.union([date, z.enum(['today', 'tomorrow'])]).optional().describe('One date; overrides from and through.'), ...filters },
    annotations: read, _meta: { securitySchemes },
  }, options => invoke({ name: 'list_tasks', options }));
  server.registerTool('list_completed_tasks', {
    description: 'List completed tasks and their editable revisions. Optional from and through filters apply to completion dates, inclusively.',
    inputSchema: filters, annotations: read, _meta: { securitySchemes },
  }, options => invoke({ name: 'list_completed_tasks', options }));
  server.registerTool('create_task', {
    description: 'Create a task, optionally with a repeat rule. Generate a UUID for id and reuse it on retries to avoid duplicates.',
    inputSchema: {
      id: z.uuid(), title: z.string().min(1), notes: z.string().nullable().optional(),
      projectId: projectId.optional(), schedule, recurrence: rule.optional(),
    },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'create_task', input }));
  server.registerTool('update_task', {
    description: 'Edit or reschedule a saved task using its latest revision and only changed fields. For a repeating task, title, notes, and schedule changes affect the current occurrence; recurrence changes affect future repeats. Projected occurrences cannot be edited directly.',
    inputSchema: { id: z.uuid(), revision, changes: taskChanges },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'update_task', ...input }));
  server.registerTool('complete_task', {
    description: 'Complete a saved task using its latest revision. Completing the current recurring task advances the recurrence.',
    inputSchema: { id: z.uuid(), revision },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'complete_task', ...input }));
  server.registerTool('delete_task', {
    description: 'Delete a saved task using its latest revision. Deleting the current recurring task advances to the next occurrence; deleting a completed occurrence removes only that history entry.',
    inputSchema: { id: z.uuid(), revision },
    annotations: destructive, _meta: { securitySchemes },
  }, input => invoke({ name: 'delete_task', ...input }));
  server.registerTool('reinstate_task', {
    description: 'Return a completed task as an ordinary active task using its latest revision. Its date defaults to today; supply date to choose another day.',
    inputSchema: { id: z.uuid(), revision, date: date.optional() },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'reinstate_task', ...input }));
  server.registerTool('reorder_tasks', {
    description: 'Move saved tasks as a block to a daily list or project list, rescheduling or changing their project as needed. Choose exactly one context: date or projectId. Projected occurrences cannot be reordered.',
    inputSchema: taskMove,
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'reorder_tasks', input }));
  server.registerTool('list_recurrences', {
    description: 'List recurrence templates, their repeat rules, future task defaults, and editable revisions. Optionally filter by project.',
    inputSchema: { projectId: projectId.optional() }, annotations: read, _meta: { securitySchemes },
  }, options => invoke({ name: 'list_recurrences', options }));
  server.registerTool('update_recurrence', {
    description: 'Edit a recurrence template using its latest revision. Title, notes, timing, and rule changes apply to future occurrences. Changing its project also moves the current task.',
    inputSchema: { id: z.uuid(), revision, changes: z.object({
      ...textChanges, rule: rule.optional(),
      time: time.nullable().optional(), endTime: time.nullable().optional(), projectId: projectId.optional(),
    }) },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'update_recurrence', ...input }));
  server.registerTool('stop_recurrence', {
    description: 'Stop a recurrence using its latest revision. Retains the current task and completed history as ordinary tasks.',
    inputSchema: { id: z.uuid(), revision },
    annotations: write, _meta: { securitySchemes },
  }, input => invoke({ name: 'stop_recurrence', ...input }));
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
