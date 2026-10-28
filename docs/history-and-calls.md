# History recovery and background calls (0.4.0)

The owner requested database-backed recovery using the login password. This
extends the PRD's original P2 backup scope; it does not upload Signal private
identities or ratchets. Install this version over the existing signed app.

## Enable and restore

New sign-ins automatically create/unlock the encrypted archive with the password
just authenticated. Existing signed-in installations must open **Pengaturan →
Backup & riwayat chat**, enter the login password, and choose **Aktifkan / pulihkan
riwayat** once. Check the last successful backup before deleting app data.
Subsequent message changes are backed up automatically after a short debounce;
background message processing and normal logout also attempt a backup.

After reinstall or clearing data, sign into the same account with the same
password. A new Signal device identity is generated; old chat content and
attachment keys are restored from the encrypted archive. Existing server call
logs load independently of the archive. Messages lost before the first backup
can only be recovered from another installation that still has their plaintext.

Changing a password in the app rewraps the archive key. An administrator reset
does not reveal old history: on a fresh installation, enter the previous backup
password to restore it, then enter the current login password and choose
**Samakan dengan password login**. Never replace an archive just because a
password fails to decrypt it.

## Encryption and concurrency

- AES-256-GCM archives with random nonces and authenticated account/key/device
  identifiers. Each device uploads its own gzip-compressed snapshot; restoration
  merges message IDs, deletion/control events and hidden-message IDs.
- A random account archive key is wrapped with AES-256-GCM using a
  PBKDF2-HMAC-SHA256 key, 600,000 iterations and a random 16-byte salt. Derivation
  runs off the UI isolate. Only the wrapped key and ciphertext reach PostgreSQL.
- Login passwords are never saved locally. The unwrapped archive key is stored
  in the existing encrypted device vault. Login-password strength limits the
  archive's resistance to offline password guessing; this requires independent
  cryptographic review alongside the existing Signal integration.
- No Signal identity, session state, auth tokens, drafts, pending uploads or local
  file paths are included. Restoring cannot fork an old device's ratchet.
- Private-schema RPCs require a live account, active session and owned device;
  no administrator history-reading endpoint is provided. Key rewrap uses a
  revision check. Per-device archive revisions reject stale background writes.
- Prototype limits: 16,000,000 base64 characters per archive (about 12 MB
  compressed ciphertext), 20 device archives, 100,000,000 characters per account.
  Failures remain visible in Backup settings and never delete the local history.

## Call notification lifecycle

The service-role-only push dispatcher sends high-priority FCM call hints with
opaque call/device IDs, voice/video type and the actual server expiry. The
Android receiver requires Google's C2DM sender permission and the currently
registered device marker. It prepares Callkit's registered headless engine and
displays the incoming notification before account preparation or chat crypto.
The ordinary Flutter background handler validates server state as a fallback.

Android 14+ requires a separate full-screen-intent setting. The app offers a
permission shortcut and retains the system call notification with answer/decline
actions when full-screen presentation is unavailable. Background decline/timeout
events update server state. Answer resumes the authenticated foreground call
service; media is never opened merely because a push arrived.

Terminal/answered call transitions enqueue dismissal hints. A losing device's
popup dismissal must not terminate the winning device's call. Recent dismissal
IDs also suppress reordered late ringing pushes. The worker expires calls when
neither app is open, keeping missed-call logs durable in PostgreSQL.

The **Panggilan** tab lists audio/video, incoming/outgoing/missed/declined status,
time, connected duration, pagination and callback. Its local cache is only an
offline convenience; reinstall loads authorized logs from the server.

## Verification

Local tests cover wrong-password/tamper rejection, fresh-vault restore, password
rewrap, unchanged-archive deduplication and call-log labels/durations. SQL tests
cover account/device isolation, malformed envelopes, key revision checks, stale
archive writes and worker-driven expiry/dismissal fanout. Disposable live clients
verify that a new vault/device restores history and call logs without inheriting
the old identity. `Android incoming-call notifications` is a manually dispatched
API-34 emulator suite for real native notification actions, cancellation, stale
push suppression and full-screen-denied fallback, without a real user login.

Physical Android 14/16 background, Doze, process-kill, lock-screen, audio/video and
OEM battery-policy acceptance remains necessary. Android force-stop cannot be
bypassed. This remains an internal technical prototype, not an audited release.
