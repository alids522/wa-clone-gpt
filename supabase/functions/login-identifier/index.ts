import { body, clients, json, rateLimit } from '../_shared/http.ts';

Deno.serve(async request => {
  try {
    const input = await body(request);
    if (typeof input.identifier !== 'string' || typeof input.password !== 'string' || input.password.length > 1024 || !/^[a-z0-9_]{3,24}$/.test(input.identifier)) return json({ error: 'Invalid credentials' }, 401);
    const { service, auth } = clients();
    await rateLimit(service, `login:${input.identifier}`);
    // Never return username -> email mappings to a public client.
    const { data: email } = await service.rpc('adoetz_login_lookup', { identifier: input.identifier });
    const { data, error } = await auth.auth.signInWithPassword({ email: email ?? 'unavailable@example.invalid', password: input.password });
    if (error || !data.session || !email) return json({ error: 'Invalid credentials' }, 401);
    if (input.verify_only === true) {
      await auth.auth.signOut({ scope: 'local' });
      return json({ ok: true });
    }
    return json({ refresh_token: data.session.refresh_token });
  } catch { return json({ error: 'Sign in unavailable. Try again later.' }, 429); }
});
