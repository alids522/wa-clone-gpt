import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.104.0';

export const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' } });
export function clients(authorization?: string) {
  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  return {
    service: createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, options),
    auth: createClient(url, anon, { ...options, global: { headers: authorization ? { Authorization: authorization } : {} } }),
  };
}
export async function hash(value: string) { return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))), b => b.toString(16).padStart(2, '0')).join(''); }
export async function body(request: Request) {
  if (request.method !== 'POST' || Number(request.headers.get('content-length') ?? 0) > 8192) throw Error('Invalid request');
  const raw = await request.text();
  if (raw.length > 8192) throw Error('Invalid request');
  return JSON.parse(raw);
}
export async function rateLimit(service: ReturnType<typeof clients>['service'], scope: string) {
  const { data, error } = await service.rpc('adoetz_rate_limit', { key_hash: await hash(scope) });
  if (error || data !== true) throw Error('Rate limited');
}
