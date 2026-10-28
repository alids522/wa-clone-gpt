import { body, clients, json, rateLimit } from '../_shared/http.ts';

Deno.serve(async request => {
  try {
    const input = await body(request);
    const { auth, service } = clients(request.headers.get('Authorization') ?? '');
    const { data: { user }, error } = await auth.auth.getUser();
    if (error || !user) return json({ error: 'Unauthorized' }, 401);
    await rateLimit(service, `turn:${user.id}`);
    const call = await auth.rpc('call_action', { call_id: input.call_id, device: input.device, operation: 'get' });
    if (call.error || !['ringing', 'connecting', 'connected'].includes(call.data?.status)) return json({ error: 'Call unavailable' }, 403);
    const encoded = Deno.env.get('ADOETZ_TURN_CONFIG_B64');
    const config = JSON.parse(encoded ? atob(encoded) : await Deno.readTextFile('/home/deno/functions/_secrets/turn.json'));
    const username = `${Math.floor(Date.now() / 1000) + 600}:${user.id}`;
    const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(config.secret), { name: 'HMAC', hash: 'SHA-1' }, false, ['sign']);
    // Coturn's documented REST credential format uses HMAC-SHA1, not a media cipher.
    const credential = btoa(String.fromCharCode(...new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(username)))));
    return json({ iceServers: [{ urls: config.urls, username, credential }], expires_in: 600 });
  } catch { return json({ error: 'Relay unavailable' }, 503); }
});
