import { body, clients, hash, json, rateLimit } from '../_shared/http.ts';

Deno.serve(async request => {
  try {
    const input = await body(request);
    const { service, auth } = clients(request.headers.get('Authorization') ?? '');
    const { data: { user }, error } = await auth.auth.getUser();
    if (error || !user) return json({ error: 'Unauthorized' }, 401);
    await rateLimit(service, `admin:${user.id}`);
    // The service RPC checks CURRENT role and status, not cached JWT claims.
    const kind = input.action === 'audit' ? 'audit' : 'users';
    const snapshot = await service.rpc('adoetz_admin_snapshot', { actor: user.id, kind });
    if (snapshot.error) return json({ error: 'Forbidden' }, 403);
    if (['list-users', 'audit'].includes(input.action)) return json({ rows: snapshot.data });
    if (typeof input.reason !== 'string' || input.reason.trim().length < 1 || input.reason.length > 200 || typeof input.password !== 'string' || input.password.length > 1024) return json({ error: 'Invalid request' }, 400);
    const stepUp = clients().auth;
    const verification = await stepUp.auth.signInWithPassword({ email: user.email!, password: input.password });
    if (verification.error || verification.data.user?.id !== user.id) return json({ error: 'Reauthentication required' }, 403);
    await stepUp.auth.signOut({ scope: 'local' });
    const code = input.action === 'create-invite' ? Array.from(crypto.getRandomValues(new Uint8Array(24)), b => b.toString(16).padStart(2, '0')).join('') : null;
    const result = await service.rpc('adoetz_admin_action', { actor: user.id, target: input.target ?? null, operation: input.action, reason: input.reason.trim(), request_id: input.request_id ?? crypto.randomUUID(), invite_hash: code ? await hash(code) : null });
    if (result.error) return json({ error: 'Action rejected' }, 403);
    return json({ ok: true, ...(code ? { invite_code: code } : {}) });
  } catch { return json({ error: 'Action unavailable' }, 400); }
});
