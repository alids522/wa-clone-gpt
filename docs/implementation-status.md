# Implementation and acceptance status — 0.2.0

The owner requested multi-device support ahead of the PRD's original P2 schedule. Each installation has independent Signal keys; a second login no longer replaces or conflicts with the first device.

| Area | Implemented | Evidence / remaining verification |
| --- | --- | --- |
| Accounts | Invite-only signup, email/username login, live roles/status, forced password replacement | Live disposable accounts verified default user role, username login, reset and revoked JWT denial |
| Multi-device | Per-device identities, encrypted fanout, own-device copies, device listing/revocation, session binding | Automated three-device crypto test and live same-account phone/tablet clients passed; physical upgrade remains |
| Existing installations | Retain original Signal address, keys/history and committed legacy outboxes; lazy adoption for old clients first registered during rollout | SQL regression and exact-envelope outbox retry test passed; install over the original APK |
| Messaging | Durable outbox, cursor catch-up, idempotency, encrypted delivered/read receipts, typing TTL, local search, pin/mute, block/report | Live encrypted send and background-controller receipt passed; OEM/Doze and process-kill chaos suite remains |
| Rich chat | Encrypted photo/video/document uploads, previews, voice recording/playback with seek/speed, replies, edits, reactions, forwarding, delete events | Live streamed ciphertext upload/download and access denial passed; microphone/camera/player behavior needs hardware QA |
| Profiles/privacy | Avatar upload, unblock, safety numbers across device sets, screenshot protection, optional biometric/device-PIN app lock | Live avatar access passed; app-lock route hiding/canceled-auth test passed; native biometric hardware QA remains |
| Calling | WebRTC audio/video, encrypted offer/answer/ICE, authoritative lifecycle/first answer, TURN credentials, Android incoming UI, call history/controls, ICE restart | Live authorized start/accept/end and credentials passed; external authenticated UDP allocation and bidirectional relay passed after VPS firewall change; actual media calls require two phones |
| Push | FCM HTTP v1 worker/queue, opaque payloads, token refresh/removal, background sync and local notifications, permission banner/deep links | Live worker and Firebase OAuth healthy; no physical FCM token registered at verification, so actual phone notification/Doze delivery is pending |
| Admin | Reauthentication, invites/revoke, suspend, roles, revoke sessions, reset/replace password, soft-delete, reports/audit | Live disposable-account acceptance passed without using the owner's password |
| Release | Stable signed APK workflow, checksum, analyzer/unit/widget/SQL CI | GitHub build and certificate checks are evidence of build integrity, not a security audit |

## Server verification (2026-10-28)

The self-hosted database has all versioned migrations installed. Firebase credentials persist privately in the functions container configuration; the push worker is running. Storage accepts the encrypted 100 MB media limit. TURN uses TCP/UDP 3478 and UDP relays 49160–49259; external binding, authenticated allocation and traffic in both directions were verified.

Disposable live accounts/files were cleaned up. Existing account count, original message count and legacy public identities were preserved. No production user account was reset as part of acceptance tests.

## Boundaries still requiring acceptance

- Update both Android 14 tablet and Android 16 phone using the stable signed APK, without uninstalling or clearing data. New devices receive future messages; existing history stays on its original device. There is no private-key restore from Supabase.
- Verify real FCM registration, background/killed-but-not-force-stopped receipt delivery, lock-screen incoming calls, microphone/camera routing, network switching and Doze/OEM behavior. Delivery requires the recipient actually decrypting and saving, so a force-stopped or offline device legitimately remains one tick.
- Exercise native vault process-death/storage-full boundaries, large-history performance, N-to-N+1 install, accessibility/screen readers and biometric enrollment changes.
- Complete independent cryptographic/license review and the PRD AC-01–AC-12 evidence before calling this a production-secure messenger.
- Some secondary PRD UX remains simplified: voice notes use a recording sheet rather than hold/swipe/lock gestures; safety verification currently compares numeric fingerprints; archive/shared-media browsing and advanced admin pagination/filtering are not complete. Groups, encrypted backup/recovery, iOS/web and group calls remain P2.

Live integration is opt-in: `flutter test test/live_acceptance_test.dart --dart-define=ACCEPTANCE_FIXTURE=<ignored-fixture-path>`. It requires disposable accounts created by `tools/server_acceptance.py`, followed by its `finish` and `cleanup` modes. An optional `ACCEPTANCE_PROXY` value can configure an HTTP CONNECT proxy for a constrained local network. Ordinary CI skips only this live test and runs the local suites.
