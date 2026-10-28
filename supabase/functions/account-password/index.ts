import { body, clients, json, rateLimit } from '../_shared/http.ts';

Deno.serve(async request => {
  try {
    const input = await body(request);
    if (typeof input.new_password !== 'string' || input.new_password.length < 12 || input.new_password.length > 1024) return json({ error: 'Use at least 12 characters' }, 400);
    const authorization = request.headers.get('Authorization') ?? '';
    const { auth, service } = clients(authorization);
    const { data: { user }, error } = await auth.auth.getUser();
    if (error || !user) return json({ error: 'Unauthorized' }, 401);
    await rateLimit(service, `password:${user.id}`);
    const account = await auth.rpc('my_account');
    if (account.error || !['active', 'reset_required'].includes(account.data?.status)) return json({ error: 'Account unavailable' }, 403);
    if (account.data.status === 'active') {
      if (typeof input.current_password !== 'string' || input.current_password.length > 1024) return json({ error: 'Reauthentication required' }, 403);
      const verifier = clients().auth;
      const step = await verifier.auth.signInWithPassword({ email: user.email!, password: input.current_password });
      if (step.error || step.data.user?.id !== user.id) return json({ error: 'Reauthentication required' }, 403);
      await verifier.auth.signOut({ scope: 'local' });
    }
    // getUser verified this JWT before its session_id is read.
    const token = authorization.replace(/^Bearer /, '').split('.')[1];
    const claims = JSON.parse(atob(token.replace(/-/g, '+').replace(/_/g, '/')));
    if (typeof claims.session_id !== 'string') return json({ error: 'Session unavailable' }, 403);
    const changed = await fetch(`${Deno.env.get('SUPABASE_URL')}/auth/v1/user`, { method: 'PUT', headers: { Authorization: authorization, apikey: Deno.env.get('SUPABASE_ANON_KEY')!, 'Content-Type': 'application/json' }, body: JSON.stringify({ password: input.new_password }) });
    if (!changed.ok) return json({ error: 'Password update unavailable' }, 503);
    const completed = await service.rpc('adoetz_password_changed', { actor: user.id, keep_session: claims.session_id });
    if (completed.error) return json({ error: 'Sign in again to complete password change' }, 409);
    return json({ ok: true });
  } catch { return json({ error: 'Password update unavailable' }, 400); }
});
