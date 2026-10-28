# Security boundaries and open gates

## Transport and local state

Only public identity/prekey material leaves the Signal store. Message and receipt content is serialized inside Signal ciphertext. Account profile fields and transport metadata remain visible to the backend. Private identity keys, sessions, drafts and local presentation text are serialized into an Android encrypted secure-storage value. Auth tokens use the same secure-storage provider, not the default plain preferences store.

Client operations serialize ratchet access. The durable vault snapshot includes both updated cryptographic state and the exact outgoing envelope before network transmission. Retries use the same client UUID and envelope. Database sends serialize per conversation before assigning the ordered cursor; uniqueness on sender/client UUID prevents duplication after a lost acknowledgement. A malformed or unauthentic message stops that chat's catch-up instead of silently skipping it.

The vault is a bounded-alpha implementation, not a scalable encrypted history database. It rewrites account state; process-kill behavior, storage capacity, Android Keystore recovery and native provider atomicity must be exercised on hardware. Do not claim the PRD chaos gates have passed.

## Identity

The third-party Dart Signal implementation is not an endorsement or audit by Signal. It implements an established protocol rather than a custom key agreement. Trust-on-first-use pins peer identities; changes fail closed. Single-device registration rejects a conflicting identity. Device loss has no automatic recovery or silent identity replacement. The initial signed prekey is retained; rotation and proactive prekey replenishment are not release-ready. Initial protocol/library and license review remain blocking beta gates.

## Backend

Raw user metadata never authorizes a role. The Auth transaction trigger consumes a hashed, unexpired, one-use invite and creates a default user account. Username uniqueness failures roll back the transaction. Private-schema helpers contain narrowly checked SECURITY DEFINER code; public wrappers use SECURITY INVOKER with explicit grants. Raw messages and conversations have membership/status RLS. Clients cannot directly insert transport messages, write roles or read invite hashes. Current status is checked on every protected RPC; suspended tokens cannot continue protected database access.

Admin Edge requests validate JWTs using getUser(), then query current role/status. Mutations require password reauthentication and a reason. The transaction refuses self-targeting and all actions against other admins in this alpha, preventing last-admin removal. No master key or admin message-decryption endpoint exists. A force-reset currently restricts the account to reset_required; it does not claim to deliver replacement credentials or recover keys. Tokens are not magically invalidated by suspension; live policies are the enforcement boundary. Full session revocation, retention and deletion workflows remain open.

Username login mappings are service-only and never returned to a client. Public login uses bounded payloads and a server-side account-keyed rate limiter; enumeration timing, distributed IP limits, signup abuse and prefix-search throttling require additional staging hardening. Rate-limit rows need a cleanup job before sustained use.

## Push and distribution

Only token registration exists in this alpha; there is no complete delivery worker. Future FCM payloads must contain opaque event/chat IDs, never content or keys. Notifications are delivery hints; server catch-up is authoritative.

Debug artifacts are clearly internal prototypes and do not provide stable update signing. Production candidates require an owner's protected keystore and environment configuration. No backend secrets, Firebase service-account keys or signing material belong in source or an APK.

## Required release evidence

Run the PRD AC-01 through AC-12 against live staging and two physical devices. Include direct REST/RLS abuse, process death at each ratchet/outbox write boundary, duplicate delivery and ACK loss, session revocation, stale notifications, changed identity handling, Android 10+ / OEM background restrictions and a signed N-to-N+1 upgrade. Obtain an external cryptographic review before claiming secure production messaging.
