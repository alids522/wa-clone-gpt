# Security boundaries and open gates

## Message and file state

Signal private identities and sessions stay in the encrypted Android vault. The backend receives public prekeys, ciphertext, profiles and transport metadata. Ratchet state and the exact outgoing ciphertext are committed together before a send; retries retain the same UUID/envelope. The native vault barrier waits for the pinned storage provider's preferences writes before transport or delivered receipts. A shared native transaction queue serializes foreground and background Flutter engines and reloads newer snapshots. Concurrent sync callers join the active operation.

Attachments use AES-256-GCM with authenticated bounded chunks, fresh keys/nonces and a ciphertext digest. File names, original MIME and content keys travel inside Signal messages. Upload streams outside the crypto transaction; only its durable completion releases the encrypted send. Private Storage policies restrict access by owner/conversation membership, status and session. Profile pictures are visible to authorized active app users and are not E2EE messages. Exporting an attachment to another application intentionally creates a plaintext copy outside the vault's control.

This remains a snapshot vault rather than a scalable encrypted history database. Hardware crash injection, Keystore recovery, filesystem capacity and temporary-file/cache retention need acceptance testing. An OS biometric/PIN prompt provides an optional UI access gate and hides routes on backgrounding; it does not make a rooted device trustworthy or bind every Signal key use to biometric hardware. Android screenshot protection is an optional OS control.

## Device identity

Each installation has its own Signal identity. New messages fan out to all observed active peer devices and the sender's other devices. TOFU pins individual identities; a changed identity fails closed. Safety numbers cover both accounts' active device-key sets and change when devices change. Signed prekeys rotate and old keys are retained for delayed messages; one-time prekeys replenish monotonically without restoring consumed IDs. Original 0.1 device IDs and ratchet addresses remain valid on upgrade, including devices first registered by old binaries during rollout.

A new device cannot recover old keys/history from a password or an administrator. No key backup or transfer is implemented. The Dart Signal library and its integration have not received independent review; compatibility, licensing and cryptographic review remain production gates.

## Backend authorization

An Auth transaction trigger consumes a hashed, unexpired, one-use invitation and creates a default user. User-editable metadata never grants a role. Private-schema helpers enforce authorization with an empty search path and explicit grants; exposed wrappers use invoker privileges. RLS protects exposed tables and private Storage. Session bindings prevent another login from borrowing a device's key identity; revocation is checked against current server sessions/status, including otherwise unexpired JWTs.

Admin requests validate bearer tokens and current role/status. Mutations require password reauthentication and a reason. SQL guards prevent self/last-admin removal. Reset revokes sessions, sets a temporary password and requires replacement; it never recovers encryption keys. Passwords and chat content do not enter audit entries. Deletion is a restricted soft deletion, not a claim of complete legal retention/erasure handling.

Username mappings and Firebase/service-role credentials are server-only. Login has an account-keyed rate limiter; distributed IP abuse, enumeration timing and large-scale quota/capacity tests still need hardening. Realtime typing channels authorize membership and have TTL; message synchronization remains authoritative.

## Push and calls

FCM data contains only opaque event IDs and event kinds, without message/file content or keys. The private worker authenticates to Firebase HTTP v1, retries durable jobs and removes unregistered tokens. Local notifications use generic copy. A push is a wake hint; delivered requires successful device decryption and durable storage. No permission or network means no guaranteed immediate notification; force-stop behavior must be tested on the actual OS/OEM.

Call signaling travels through authenticated encrypted device messages. Server call state binds caller/callee devices and enforces first acceptance, timeout and busy status. TURN credentials require an active authorized call and expire after ten minutes. TURN relays media encrypted by WebRTC; it is not an admin media-decryption endpoint. Provider firewall ports and real microphone/camera/network-switching behavior are separate acceptance requirements.

## Distribution and acceptance

Signed candidate builds use the protected stable keystore and increasing workflow build numbers. Debug alpha APKs have a different signing channel and should not replace persistent signed installations. No backend secret, Firebase service account or signing key belongs in source or an APK.

Local crypto, transactional outbox, streaming upload, multi-device receipts and widget tests plus PostgreSQL authorization/upgrade regressions provide development evidence. Live disposable-account tests exercised Auth/admin, encrypted messages/files, avatar access, call authorization and storage/RPC denial. Complete PRD AC-01–AC-12, native fault injection, two-phone/OEM tests and independent review before claiming production readiness.
