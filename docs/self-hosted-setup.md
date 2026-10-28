# Self-hosted deployment and upgrades

The owner's deployment is `https://supabase.adoetz52.my.id`. The foundation and subsequent migrations are installed; accounts and the administrator already exist. Do not bootstrap another owner or rerun old migrations on a populated server.

## Database

Back up Auth, public/private application schemas and Storage metadata. Test every migration in a separate database first, then apply only pending files from `supabase/migrations/` in filename order, each in a transaction with ON_ERROR_STOP. `private` must stay outside the Data API exposed schemas. `tools/server_upgrade.py` also records normalized SQL hashes in `private.deployment_versions` and refuses altered installed migrations.

The 0.2 upgrade adds account devices and session bindings without replacing original keys. Later migrations repair push job claiming and adopt matching devices registered by old binaries during rollout. Never delete `public.devices`, prekeys, messages or Auth users to solve a second-device login problem.

Keep email/password enabled, confirmation disabled as selected by the owner, password minimum 12 and Auth rate limits enabled. Invitation checks run inside the signup transaction, including calls made outside Flutter. Existing admins create/revoke one-use invitations through the app.

## Functions and private configuration

Copy `_shared`, `login-identifier`, `admin`, `account-password`, `push-dispatch` and `turn-credentials` from `supabase/functions/` to the mounted functions volume, retaining relative imports. Preserve the runtime's `main` and unrelated functions. Username login is public; protected functions validate their own JWT/role/call authorization. Inspect actual self-hosted gateway verification settings rather than assuming cloud CLI settings configure the local main worker.

Built-in SUPABASE_URL/ANON_KEY/SERVICE_ROLE_KEY remain on the server. Add persistent functions environment variables:

- `FIREBASE_SERVICE_ACCOUNT_B64`: base64 of the correct Firebase service-account JSON.
- `ADOETZ_TURN_CONFIG_B64`: base64 JSON containing `urls` and a strong private coturn shared `secret`.

These are secrets. Keep Compose `.env` and backups mode 600, never commit them or put them in Dart config. The runtime may not allow arbitrary filesystem reads; environment configuration is authoritative, with a private-file fallback only for compatible hosts. `tools/configure_server_services.py` persists the environment mappings and encrypted media size limit for this installation. Environment changes require recreating only the affected services; code changes require restarting functions. After container recreation, this installation's Kong may need a graceful `kong reload` to refresh upstream addresses.

## Storage, worker and TURN

`chat-media` and `avatars` are private buckets created by SQL, with membership/owner/session policies. Set the Storage service FILE_SIZE_LIMIT and chat-media limit to 110000000 to fit encrypted 100 MB files. Avatar limit is 5 MB. Do not make either bucket public.

`tools/push_worker.py` runs privately in `adoetz-push-worker`, dispatching every five seconds using the service-role key from a private env file. `push-dispatch` authenticates to Firebase HTTP v1, retries jobs and cleans expired orphan media. Check its HTTP status/counters without printing credentials. `tools/check_firebase.py` performs a validation-only request and sends no notification; a missing test device token is not proof of phone delivery.

`adoetz-turn` uses coturn with short-lived shared-secret credentials, TCP/UDP 3478 and UDP relays 49160–49259. Open those inbound ports in both the host and provider firewall. Configure the correct public/private IP mapping. Deny relay access to private/internal addresses and retain quotas. An external STUN binding check alone is insufficient: verify authenticated allocation and traffic through an allocated relay port in both directions. The owner's provider firewall change passed those checks on 2026-10-28.

## Acceptance and APK update

Run the isolated SQL tests (`authorization.sql`, `devices_calls_storage.sql`, `legacy_upgrade.sql`) with the actual migrations. Use `tools/server_acceptance.py` to prepare disposable live users, run `test/live_acceptance_test.dart`, then run `finish` and `cleanup`. This exercises Auth/admin as well as direct REST/RPC/Storage denial and avoids existing users' passwords. Keep generated fixture credentials private and remove them afterward.

Install the stable signed 0.2 APK over the existing signed app on every participating device. Do not uninstall or clear data: keys/history cannot be restored from Supabase. Allow notifications from the app's banner/settings and test real token registration, background receipts, incoming calls on the lock screen and a Wi-Fi/mobile network switch. New devices receive future messages; history stays on the original device. A recipient that is offline or force-stopped can correctly remain one tick until it actually receives and saves the message.

Back up the stable signing key privately. GitHub's Signed Android candidate workflow builds the update and publishes an artifact; it does not publish a public release automatically.
