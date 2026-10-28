# PRD implementation status

This tracks the actual 0.1.0 code, not the complete beta promised by the PRD.

| Domain | Implemented | Still required |
| --- | --- | --- |
| App shell | Branding, Android package, responsive screens, system/dark/light themes, offline/empty/error states, local preview | Full screen-reader and physical-device QA |
| Auth | Invite transaction trigger; user default role; username/email sign-in; secure session storage; logout | Live staging integration; stronger public registration abuse controls; device-replacement flow |
| Profiles | Name/bio editing, prefix search, private raw profile reads, server block enforcement | Avatar upload, unblock UI, reporting workflow, discoverability setting UI |
| Text messages | Signal library; persistent state; changed-key rejection; encrypted outbox; idempotent sends; catch-up; encrypted receipt events; draft/search/pin/mute | External review, safety-number UI/QR, native interop, crash-injection and multi-device tests; rotation/replenishment; encrypted edits/reactions/replies/delete events |
| Storage | Android encrypted vault, backups disabled | Large-history encrypted database, quotas, migrations, native vault fault injection, safe cache management |
| Admin | Live authorization, step-up verification, invitations, suspension, restricted pending-reset status, append-only service audit | Pagination, invite revoke UI, secure temporary-password handoff, session revoke orchestration, reviewed deletion/retention, role management |
| Push | Firebase initialization/resources, contextual permission, token refresh/registration, foreground sync hint handler | Durable HTTP v1 worker, background notification display/deep links, token cleanup, Doze/OEM tests |
| Rich chat | Local text search | Encrypted photo/video/document/voice-note transport and previews |
| Calling | Navigation hides unavailable calls | WebRTC, TURN credential service, authenticated signaling, state machine, Android foreground/background incoming-call integration |
| Release | Automated APK/checksum + CI artifact, signed candidate workflow, protected local keystore and encrypted Actions signing secrets | Protected environment review, real install/upgrade QA, release publication, policy approvals |

## Configuration pending from the owner

- Supabase client configuration now targets `https://supabase.adoetz52.my.id`; Auth is reachable and email auto-confirmation is enabled. The owner is manually installing the SQL/functions. The inactive cloud project is untouched.
- Firebase configuration for `com.adoetzchat.messenger` is present locally and stored as an encrypted Actions secret.
- The initial stable signing key is generated, excluded from Git, restricted to the local Windows account and configured in encrypted Actions secrets. Back it up before distributing persistent test installs.
- TURN provider and budget before implementing and validating internet calling.

## Acceptance evidence

Local Signal tests cover round-trip encryption after serialization, tamper rejection and identity changes. Widget tests cover actual preview navigation/send state and constrained screens. GitHub runs the real SQL migration and adversarial role tests on PostgreSQL. A successful APK build proves compilation, not remote delivery, cryptographic audit or production readiness.
