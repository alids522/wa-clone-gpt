# Implementation and acceptance status — 0.4.0

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
| Push | FCM HTTP v1 worker/queue, opaque payloads, token refresh/removal, background sync and local notifications, permission banner/deep links | Owner confirmed ordinary chat notifications on physical devices; native incoming-call cold-start and dismissal paths added in 0.4.0, with Android 14/16 acceptance still required |
| Admin | Reauthentication, invites/revoke, suspend, roles, revoke sessions, reset/replace password, soft-delete, reports/audit | Live disposable-account acceptance passed without using the owner's password |
| Release | Stable signed APK workflow, checksum, analyzer/unit/widget/SQL CI | GitHub build and certificate checks are evidence of build integrity, not a security audit |

## Server verification (2026-10-28)

The self-hosted database has all versioned migrations installed. Firebase credentials persist privately in the functions container configuration; the push worker is running. Storage accepts the encrypted 100 MB media limit. TURN uses TCP/UDP 3478 and UDP relays 49160–49259; external binding, authenticated allocation and traffic in both directions were verified.

Disposable live accounts/files were cleaned up. Existing account count, original message count and legacy public identities were preserved. No production user account was reset as part of acceptance tests.

## Boundaries still requiring acceptance

- Update both Android 14 tablet and Android 16 phone using the stable signed APK, without uninstalling or clearing data. Enable the encrypted history archive before clearing data; fresh login restores archived messages using the login password. Signal private identities and ratchets stay device-specific.
- Verify real FCM registration, background/killed-but-not-force-stopped receipt delivery, lock-screen incoming calls, microphone/camera routing, network switching and Doze/OEM behavior. Delivery requires the recipient actually decrypting and saving, so a force-stopped or offline device legitimately remains one tick.
- Exercise native vault process-death/storage-full boundaries, large-history performance, N-to-N+1 install, accessibility/screen readers and biometric enrollment changes.
- Complete independent cryptographic/license review and the PRD AC-01–AC-12 evidence before calling this a production-secure messenger.
- Some secondary PRD UX remains simplified: voice notes use a recording sheet rather than hold/swipe/lock gestures; safety verification currently compares numeric fingerprints; archive/shared-media browsing and advanced admin pagination/filtering are not complete. Groups, iOS/web and group calls remain P2. Password-wrapped encrypted history recovery was added at the owner's request; see [history and calls](history-and-calls.md).

Live integration is opt-in: `flutter test test/live_acceptance_test.dart --dart-define=ACCEPTANCE_FIXTURE=<ignored-fixture-path>`. It requires disposable accounts created by `tools/server_acceptance.py`, followed by its `finish` and `cleanup` modes. An optional `ACCEPTANCE_PROXY` value can configure an HTTP CONNECT proxy for a constrained local network. Ordinary CI skips only this live test and runs the local suites.

## 0.3.0 notification and interface fixes

The signed 0.2.0 APK lost `ic_notification` during Android resource shrinking. The notification plugin failed before FCM token registration, while the UI showed a misleading generic Play Services/permission error. The release now explicitly keeps dynamic resources and CI inspects the built APK resource table; the regression check rejects the old APK. Firebase initializes explicitly before background registration. Setup, Android/channel permission, token acquisition and server registration have distinct states, safe diagnostic codes and retry. Settings offer a local notification test and Android/full-screen call settings. A successful local notification does not prove remote FCM delivery.

Media menus distinguish photos, videos, camera capture and documents, with up to ten selections and captions. Bounded JPEG thumbnails and video duration remain inside Signal payloads. Inline image/video bubbles open an internal image/video viewer; gallery/download/save-as exports require user action. Transfers show progress, cancellation and retry. A cancellation regression verifies that an in-flight upload is removed from the durable outbox without publishing a message. Temporary picked copies are cleaned only within the app cache.

Chat/header/list/composer spacing is reduced while keeping touch controls usable. Call screens show connection state/duration, a control dock, draggable local video and camera flip, and an ongoing-call bar allows returning after minimizing. Root Back returns other tabs to Chats, then requires two presses within two seconds to background the UI. It does not force-stop the process or revoke push registration. Widget tests cover normal nested Back, timeout, small screens, large text, landscape call controls, inline media and save affordances.

Actual Android MediaStore/SAF export, microphone/camera routing and screen-off notification delivery on the owner's two physical devices still need install-time acceptance. The existing database/functions do not require a migration for this update.

## 0.4.0 history and incoming calls

Password-wrapped encrypted archives, automatic fresh-login restoration, a durable Calls tab, native call notification preparation, background decline handling, cancellation hints and server-driven missed-call expiry are implemented. Disposable live clients restored chat and server call logs into a fresh vault with a different Signal identity. Local/SQL regression tests passed. The API-34 native notification workflow and two physical devices provide separate Android acceptance evidence; see [history and calls](history-and-calls.md).
