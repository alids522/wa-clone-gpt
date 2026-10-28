import { clients, json } from '../_shared/http.ts';

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
let cached: { access_token: string; until: number; project: string } | undefined;
async function credentials(stage: (value: string) => void) {
  if (cached && cached.until > Date.now() + 60000) return cached;
  stage('credential-source');
  const encodedAccount = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_B64');
  const account = JSON.parse(encodedAccount ? atob(encodedAccount) : await Deno.readTextFile('/home/deno/functions/_secrets/firebase-service-account.json'));
  const encoded = (v: unknown) => b64url(new TextEncoder().encode(JSON.stringify(v)));
  const now = Math.floor(Date.now() / 1000);
  const claim = `${encoded({ alg: 'RS256', typ: 'JWT' })}.${encoded({ iss: account.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: 'https://oauth2.googleapis.com/token', iat: now, exp: now + 3600 })}`;
  const pem = account.private_key.replace(/-----[^-]+-----/g, '').replace(/\s/g, '');
  stage('credential-import');
  const key = await crypto.subtle.importKey('pkcs8', Uint8Array.from(atob(pem), c => c.charCodeAt(0)), { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(claim));
  stage('oauth-request');
  const response = await fetch('https://oauth2.googleapis.com/token', { method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${claim}.${b64url(new Uint8Array(signature))}` }), signal: AbortSignal.timeout(10000) });
  stage(`oauth-${response.status}`);
  if (!response.ok) throw Error('FCM authentication unavailable');
  const token = await response.json();
  cached = { access_token: token.access_token, until: Date.now() + token.expires_in * 1000, project: account.project_id };
  return cached;
}
Deno.serve(async request => {
  if (request.method !== 'POST' || request.headers.get('Authorization') !== `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`) return json({ error: 'Unauthorized' }, 401);
  let stage = 'start';
  try {
    const credential = await credentials(value => stage = value);
    stage = 'storage-cleanup';
    const { service } = clients();
    const orphans = await service.rpc('adoetz_orphan_media');
    if (!orphans.error) {
      for (const object of orphans.data as Array<{ bucket_id: string; name: string }>) {
        await service.storage.from(object.bucket_id).remove([object.name]);
      }
    }
    stage = 'queue';
    const jobs = await service.rpc('adoetz_claim_push_jobs');
    if (jobs.error) throw Error('Queue unavailable');
    let sent = 0, removed = 0, retry = 0;
    await Promise.all((jobs.data as Array<{ id: number; token: string; event_id: string; kind: string; created_at: string }>).map(async job => {
      if (job.kind === 'call' && Date.now() - Date.parse(job.created_at) > 45000) {
        await service.rpc('adoetz_finish_push_job', { job: job.id }); removed++; return;
      }
      try {
        const response = await fetch(`https://fcm.googleapis.com/v1/projects/${credential.project}/messages:send`, { method: 'POST', headers: { Authorization: `Bearer ${credential.access_token}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ message: { token: job.token, data: { event_id: job.event_id, kind: job.kind }, android: { priority: 'HIGH', ttl: job.kind === 'call' ? '45s' : '86400s' } } }), signal: AbortSignal.timeout(10000) });
        if (response.ok) { await service.rpc('adoetz_finish_push_job', { job: job.id }); sent++; }
        else {
          const result = await response.json();
          const invalid = result.error?.details?.some((d: { errorCode?: string }) => d.errorCode === 'UNREGISTERED') === true;
          if (invalid) { await service.rpc('adoetz_finish_push_job', { job: job.id, invalid_token: true }); removed++; }
          else retry++;
        }
      } catch { retry++; }
    }));
    return json({ sent, removed, retry });
  } catch (error) { return json({ error: 'Push dispatch unavailable', stage, error_type: error instanceof Error ? error.name : 'unknown' }, 503); }
});
