# Self-hosted Supabase deployment

The owner selected `https://supabase.adoetz52.my.id`. Its Auth endpoint is reachable and email auto-confirmation is enabled. A readiness check found that the Adoetz `public.profiles` table is not installed yet. The supplied anon key configures the client; database DDL and server function deployment require administrator access.

The app build is configured through repository Actions variables and an encrypted Firebase configuration secret. Neither the local staging configuration nor google-services.json is committed.

## Database

Review and apply `supabase/migrations/20261028011508_adoetz_foundation.sql` in a single transaction from Studio's SQL editor or an administrator psql connection. Inspect existing tables first. Keep `private` out of the Data API exposed schema list. Do not grant arbitrary SQL or service credentials to the app.

Confirm all migration statements succeed, then use the README bootstrap procedure to create an invitation, register the owner and promote the owner account. The CI fixture tests are isolated; live Auth/RLS validation is still required.

## Edge Functions

Copy these complete folders into your self-hosted Supabase `volumes/functions/` directory:

- `supabase/functions/_shared/`
- `supabase/functions/login-identifier/`
- `supabase/functions/admin/`

Keep their relative paths intact. Do not overwrite the runtime's existing `main` worker. The functions runtime needs the server's SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY; these stay on the server. The admin function validates bearer tokens itself and performs live authorization. Username login is public and rate limited, so it must be reachable without a logged-in user JWT; review the self-hosted main-worker/gateway verification settings instead of relying on cloud-only function deployment configuration.

Restart the functions service after copying code. The current Supabase self-hosting setup uses `sh run.sh restart functions`; older Compose installations may use `docker compose restart functions`. Inspect the actual deployment before choosing a command. Environment changes require recreating the service, not just restarting it.

See the [official self-hosted functions deployment guide](https://supabase.com/docs/guides/self-hosting/self-hosted-functions) and [Docker deployment guide](https://supabase.com/docs/guides/self-hosting/docker).

## Acceptance checks

Check invite rejection through direct Auth signup, valid owner signup, role=user by default, server-mediated username login, two-account chat, duplicate-send rejection, cross-user REST/RPC denial, suspended JWT denial and step-up admin actions. Confirm that Firebase token registration succeeds on a physical Android device. Background push delivery still requires a server dispatch worker.
