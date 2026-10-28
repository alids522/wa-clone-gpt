# Adoetz Chat

Android-first Flutter messenger based on `Adoetz_Chat_PRD_v1.0.md`.
Application ID: `com.adoetzchat.messenger`. Android 10+. Flutter 3.44.1 / Dart 3.12.1.

**0.2.0 is an internal technical prototype. Independent security review and physical-device acceptance remain release gates.**

## What works in this alpha

- Midnight Blue, Ice Blue and persistent system theme; Indonesian interface.
- Clearly labeled local preview that works without backend credentials. Preview sends remain queued and never claim remote delivery.
- Invite-only username/email/password registration and email or server-mediated username sign-in.
- Profiles, prefix contact discovery, one-to-one conversations, pin/mute and local search.
- Signal Protocol text encryption using `libsignal_protocol_dart`, persistent identity/prekeys/sessions, trust-on-first-use and rejection of changed identity keys.
- Android encrypted vault for sessions, drafts, message cache, ratchet state and durable outbox; ciphertext and ratchet are committed together before transport.
- Idempotent server sends, paginated cursor catch-up, Realtime hints, encrypted delivery/read receipt events, read receipt preference, retry backoff and blocking.
- Current server-side role/status checks. Admin account lists, suspend/unsuspend, restricted reset-pending state, one-time invites, step-up password verification and audit logs.
- Optional Firebase client initialization, contextual notification permission and protected token registration.
- Multi-device login with independent Signal identities, encrypted fanout to peers and your other devices, per-device push tokens and session revocation. Existing keys and history are retained during upgrade.
- Encrypted photo/video/document attachments, durable upload queues, voice recording/playback, replies, edits, reactions, forwarding and deletion events.
- Profile pictures, unblock/report actions, safety numbers and optional Android screenshot protection.
- FCM HTTP v1 dispatch queue, background decryption and delivered receipts, private local notifications and notification navigation.
- Voice/video WebRTC calls with encrypted signaling, short-lived TURN credentials, Android incoming-call integration, call history, mute/speaker/camera controls and ICE restart.
- Administrator invite revocation, role changes, session revocation, temporary-password resets and mandatory user password replacement.
- GitHub Actions analysis, tests, APK + SHA-256 artifact, isolated PostgreSQL authorization tests and a separate secret-gated signed candidate workflow.

## Run locally

```sh
flutter pub get --enforce-lockfile
flutter run
```

No configuration is required to explore the local preview. For live accounts, copy `config/staging.example.json` to `config/staging.json`, supply the project URL and **publishable** key, deploy the backend below, then:

```sh
flutter run --dart-define-from-file=config/staging.json
```

Never include Supabase secret/service-role keys in client configuration.

## Supabase staging setup

The configured backend is the owner's self-hosted server, `https://supabase.adoetz52.my.id`. See `docs/self-hosted-setup.md` and `docs/implementation-status.md`. The unrelated Supabase Cloud project is untouched. Test all migrations in an isolated database before applying upgrades; back up live Auth and app data first.

1. Review `supabase/migrations/20261028011508_adoetz_foundation.sql` and apply it using the SQL editor or the Supabase CLI migration workflow. The `private` schema must not be exposed by the Data API.
2. Enable email/password signup, disable email confirmation as specified in the PRD, and set the password minimum to 12. The Auth insert trigger validates and consumes invites atomically, including direct public signup calls. Keep provider rate limits enabled.
3. Deploy the `login-identifier` and `admin` Edge Functions and the shared module. `supabase/config.toml` contains their JWT-gateway settings; each protected request explicitly validates its bearer JWT. The built-in server environment provides service credentials; do not add them to Flutter.
4. Bootstrap an invitation from the SQL editor with a cryptographically random code. Store its SHA-256 hash, never the code, in `private.invitations`. Example shape (replace the placeholder with a locally generated random value):

```sql
insert into private.invitations(token_hash, expires_at)
values (encode(extensions.digest('REPLACE_WITH_RANDOM_48_HEX_CHARACTER_CODE', 'sha256'),'hex'), now() + interval '7 days');
```

5. Register the first user with that code, then promote that exact account ID manually:

```sql
update private.accounts set role = 'admin' where id = 'REPLACE_WITH_OWNER_UUID';
```

6. Sign in again; create subsequent invitations in Settings -> Administration. Do not grant client writes to account roles or status. Validate the adversarial tests against real staging Auth and REST before any sensitive use.

## Firebase setup

Register the Android app as `com.adoetzchat.messenger`. Place its configuration at the ignored path `android/app/google-services.json`, then run:

```sh
python tools/configure_firebase.py android/app/google-services.json
```

Set `FIREBASE_ENABLED` to `true` in the local Dart configuration. The script generates native Firebase resources. Server dispatch uses `push-dispatch` and `tools/push_worker.py`; the Firebase service account remains in the server's private configuration. No plaintext messages or private keys are sent in push payloads.

## GitHub builds

Pushing `main` starts **Android alpha** and **Backend authorization**. Download `adoetz-chat-android-alpha-N` from the successful Android workflow's Artifacts section. It contains the APK and `SHA256SUMS.txt`.

Optional repository Actions variables: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`.
Optional Actions secret: `GOOGLE_SERVICES_JSON` (the JSON file contents).

Alpha APKs use runner-local **debug signing** for installation tests. Their keys can change between runners; upgrading across different debug signatures may require uninstalling and loses local app data. They are not the private beta distribution channel.

**Signed Android candidate** is manual and requires the `production` environment and these secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `GOOGLE_SERVICES_JSON`

It also requires the Supabase variables above. Configure GitHub environment protection before using it. Preserve and back up the signing key. This workspace has an initial protected local keystore at `android/app/adoetz-release.jks` and ignored signing metadata at `config/signing.local.json`; encrypted signing secrets are configured in GitHub Actions. Never commit either local file. This workflow uploads a candidate artifact; it does not publish a release. Verify increasing version codes across workflows before distributing upgrades.

## Verification

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub
```

Backend CI creates an isolated PostgreSQL 17 database, applies the actual migration and checks invite enforcement, role escalation denial, member isolation, idempotent sends, blocks and suspended-token restrictions. These tests use a minimal Auth contract fixture and do not replace a real Supabase staging acceptance test.

## Remaining PRD gates

See `docs/implementation-status.md` and `docs/security.md` for evidence and remaining acceptance gates. Update every participating device to 0.2.0 using the stable signed APK, without uninstalling or clearing app data. Original 0.1.0 history remains readable on its original device; a newly added device receives future messages and does not receive old private keys from the server. Group chat and encrypted backup remain the PRD's P2 scope.

The selected Signal dependency uses GPL-3.0. See `THIRD_PARTY_NOTICES.md`; confirm distribution licensing before a release. No security audit or production readiness is claimed.
