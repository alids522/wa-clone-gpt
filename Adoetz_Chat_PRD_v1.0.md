# ADOETZ CHAT
## Product Requirements Document (PRD) v1.0

**Produk:** Adoetz Chat  
**Android application ID:** `com.adoetzchat.messenger`  
**Platform pertama:** Android (Flutter)  
**Backend:** Supabase managed (Auth, PostgreSQL, Realtime, Storage, Edge Functions)  
**Notifikasi:** Firebase Cloud Messaging (FCM)  
**Panggilan:** WebRTC + layanan STUN/TURN  
**Distribusi:** APK private melalui GitHub Actions / GitHub Releases  
**Tema:** Midnight Blue Dark + Ice Blue Light  
**Status:** Spesifikasi desain dan perencanaan; belum diimplementasikan  
**Tanggal:** 28 Oktober 2026  
**Pemilik produk:** Adoetz Chat Project

> **Konvensi keputusan:** **CONFIRMED** = keputusan dari diskusi produk; **PROPOSED** = rekomendasi yang menjadi asumsi kerja; **GATE** = harus dibuktikan melalui prototipe / pengujian sebelum dinyatakan siap rilis.

---

# 1. Ringkasan eksekutif

Adoetz Chat adalah aplikasi pesan privat berbasis Flutter, Android-first, dengan akun username/email/password, pencarian pengguna berdasarkan username, pesan 1:1 terenkripsi end-to-end, file dan voice note, push notification, panggilan suara/video, serta dashboard admin untuk mengelola akun. Pengguna baru selalu berstatus `user`; hanya petugas terotorisasi dapat memperoleh role `admin`. Registrasi menggunakan undangan, dan email tidak perlu diverifikasi pada tahap pendaftaran sesuai keputusan pemilik produk.

Aplikasi menempatkan **privasi, kelancaran chat saat koneksi tidak stabil, dan kejelasan status pesan** di atas animasi dekoratif. Server menerima ciphertext, bukan pesan plaintext, dan tidak menyimpan private key pengguna. Admin dapat menonaktifkan, mereset kredensial akun, dan menghapus pengguna, tetapi tidak dapat membaca riwayat E2EE.

**Janji produk yang benar:** konten pesan dan lampiran yang dienkripsi di perangkat tidak dapat dibaca server dengan implementasi E2EE yang benar. **Bukan janji produk:** metadata nol, delivery push selalu instan, pemulihan riwayat tanpa backup kunci, atau semua jenis HP pasti menerima layar panggilan penuh.

## 1.1 Keputusan yang sudah dikonfirmasi

- Nama aplikasi: **Adoetz Chat**; application ID `com.adoetzchat.messenger`.
- Flutter; APK dibangun menggunakan **GitHub Actions**.
- Supabase sudah dimiliki pengguna; memakai managed backend untuk tahap awal.
- Form registrasi mencakup **username, email, password**, tanpa kewajiban verifikasi email.
- Ada **login**, **logout**, dan hak akses `user` serta `admin`; default sign up = `user`.
- Admin dapat mengelola pengguna, menghapus akun, dan mengganti/reset password melalui operasi privileged.
- UI **Black & Blue**, tersedia **Light Mode** dan mengikuti tema sistem.
- E2EE, pesan, lampiran, notifikasi, serta voice/video call adalah arah produk yang diminta.

## 1.2 Asumsi produk yang perlu disetujui sebelum rilis

- **PROPOSED:** registrasi *invite-only* dengan kode undangan satu kali pakai; semua pembuatan akun dipaksa melewati kontrol backend.
- **PROPOSED:** Android 10+ sebagai target awal (final minimum SDK ditentukan oleh kompatibilitas Flutter/plugin).
- **PROPOSED:** satu **perangkat aktif untuk kunci E2EE per akun** pada v1; tambah multi-device setelah protokol dan recovery selesai.
- **PROPOSED:** grup, video grup, edit/forward lanjutan, backup E2EE, dan iOS masuk pascarilis awal kecuali waktu implementasi memungkinkan.
- **PROPOSED:** admin lebih aman melakukan **force-reset** atau password sementara daripada mengetahui kata sandi lama pengguna.
- **GATE:** library kriptografi E2EE yang dipilih harus mendukung audit, interoperabilitas Flutter/Android, penyimpanan kunci aman, dan pengujian ketahanan crash.
- **GATE:** uji panggilan saat aplikasi background, idle/Doze, layar terkunci, dan Android dengan pembatasan baterai OEM.

# 2. Masalah, target, dan batasan

## 2.1 Masalah pengguna

1. Komunikasi antaranggota kelompok privat membutuhkan akun sederhana tanpa nomor telepon.
2. Pengguna ingin tahu apakah pesan masih antre, sudah diterima server, sudah sampai perangkat tujuan, atau dibaca.
3. File, chat, dan panggilan harus terlindungi tanpa memberikan akses plaintext kepada admin/backend.
4. Pengelola komunitas perlu memblokir, menangguhkan, dan menghapus akun tanpa menyentuh isi percakapan.
5. Instalasi aplikasi masih melalui APK; update tidak boleh memaksa uninstall dan kehilangan data lokal.

## 2.2 Sasaran terukur (target internal awal, bukan klaim kemampuan provider)

| ID | Sasaran | Target uji penerimaan |
|---|---|---|
| OBJ-01 | Sukses registrasi legal | >= 99% pada lingkungan staging sehat (tanpa salah input) |
| OBJ-02 | Respons UI saat tindakan normal | p95 < 150 ms untuk interaksi lokal (scroll, buka menu, mengetik) pada perangkat uji |
| OBJ-03 | Waktu melihat pesan baru | p95 < 3 dtk saat kedua perangkat online, jaringan uji stabil |
| OBJ-04 | Tidak kehilangan pesan akibat reconnect | 0 kehilangan/duplikasi akibat retry dalam suite chaos test |
| OBJ-05 | Enkripsi konten | 100% pesan/lampiran diuji ciphertext sebelum upload |
| OBJ-06 | Tidak ada eskalasi role | 0 keberhasilan akses admin oleh role user di pengujian otorisasi |
| OBJ-07 | Stabilitas | crash-free sessions >= 99,5% pada beta internal |
| OBJ-08 | APK dapat di-update | seluruh pengujian upgrade dengan signing key yang sama berhasil tanpa kehilangan chat lokal |

Angka di atas merupakan **acceptance targets** sementara. Pengukuran dan minimum hardware disepakati saat beta.

## 2.3 Non-goals versi pertama

- Tidak mendukung SMS atau telepon jaringan seluler.
- Tidak membuka pendaftaran umum tanpa kontrol undangan.
- Tidak menyediakan admin untuk membaca/mendekripsi pesan.
- Tidak menjanjikan menghapus salinan pesan yang sudah discreenshot/diekspor pihak penerima.
- Tidak menjamin panggilan masuk dapat muncul setelah Android melakukan **force-stop** terhadap aplikasi.
- Tidak menyediakan multi-device tersinkron penuh pada versi awal.
- Tidak membuat protokol kriptografi sendiri.

# 3. Persona, role, dan model perizinan

**Pengguna baru (`user`)**: mendaftar melalui undangan, mengisi profil, mencari username, membuat percakapan, mengirim pesan, menerima notifikasi, melakukan panggilan, mengunci aplikasi, mengelola preferensi pribadi, dan logout.

**Administrator (`admin`)**: memiliki semua hak sebagai user ditambah mengelola akun (daftar, cari, detail, suspend/unsuspend, revoke session, force password reset, soft-delete/hard-delete sesuai kebijakan) dan melihat audit log tindakan admin. Admin **tidak** berhak membaca ciphertext sebagai plaintext, key privat, ataupun pesan yang tidak dialamatkan kepadanya.

**Operator sistem (server-side service)**: melakukan tugas terbatas seperti kirim push, membersihkan file usang, proses undangan, autentikasi yang memerlukan keistimewaan, dan mengaudit operasi. Bukan akun Flutter dan tidak terekspos ke klien.

| Aksi | Tamu | User | Admin | Server privileged |
|---|---|---|---|---|
| Register pakai invite valid | Ya | Tidak relevan | Tidak relevan | Memvalidasi |
| Login, logout | Ya / sendiri | Sendiri | Sendiri | Memverifikasi token |
| Edit profil sendiri | Tidak | Ya | Ya | Guardrails |
| Cari username publik | Tidak / terbatas | Ya | Ya | Rate limit |
| Baca ciphertext percakapan | Tidak | Hanya anggota | Hanya anggota | Dapat mengelola transport, bukan dekripsi |
| Kirim pesan/call | Tidak | Ya, jika aktif | Ya, jika aktif | Validasi akses |
| Lihat daftar akun administratif | Tidak | Tidak | Ya | Ya |
| Suspend/delete user | Tidak | Tidak | Ya, dibatasi | Menjalankan |
| Reset password user lain | Tidak | Tidak | Ya, dibatasi | Menjalankan |
| Mengubah role | Tidak | Tidak | Admin terotorisasi, bukan diri sendiri sembarangan | Menjalankan |
| Membaca private key orang lain | Tidak | Tidak | Tidak | Tidak |

**RBAC invariants:** default role selalu `user`; aplikasi Flutter tidak bisa menulis role sendiri; otorisasi tidak bertumpu pada tampilan tombol; role diambil dari data server yang tepercaya (contohnya `app_metadata` atau tabel role dengan RLS/SQL policy yang sesuai); perubahan role memiliki audit log dan aturan anti-penghapusan admin terakhir.

# 4. Ruang lingkup dan prioritas

**P0 / Foundation (wajib untuk prototipe tertutup):** app shell, 2 tema, onboarding, invite-only register, login email/username dan password, logout, profil, cari user, admin minimal, RLS, audit log, secure session, struktur GitHub Actions, release signing, error UI.

**P0 / Secure Messaging (wajib sebelum klaim messenger aman):** library E2EE tervalidasi, prekey service, verifikasi key, single-device identity, 1:1 text E2EE, antrean offline, idempotensi, receipts, Realtime + catch-up sync, push metadata-minimal, block/report.

**P1 / Rich Chat:** lampiran foto/video/dokumen terenkripsi, pratinjau lokal, voice notes terenkripsi, reply, reaction, delete for me/everyone dengan batas yang jelas, edit dengan riwayat peristiwa terenkripsi, pencarian lokal, mute, pinned chat.

**P1 / Calling:** WebRTC 1:1 voice/video, incoming call foreground/background/lock screen sesuai izin dan perangkat, call log, jaringan berubah, fallback ke voice, TURN, batas timeout.

**P2 / Setelah beta:** group chats E2EE, multi-device, backup terenkripsi dan recovery key, iOS/web, group call, desktop, penjadwalan pesan, advanced moderation, richer media editor.

**Aturan rilis:** fitur yang gagal security gate tidak dipaksakan ke produksi; jika E2EE belum lolos, rilis hanya boleh diberi label **internal technical prototype** dan tidak digunakan mengirim data sensitif.

# 5. Informasi arsitektur navigasi (IA)

## 5.1 Struktur utama

```text
Splash / bootstrap
 ├── Belum login -> Welcome -> Sign In | Enter Invite -> Sign Up
 ├── Sesi kedaluwarsa -> Session Expired -> Sign In
 ├── Perangkat/kunci hilang -> Key Recovery / Replace Device Warning
 └── Login aktif -> Main App
      ├── Chats -> Chat Detail -> Contact Info / Media / Search
      ├── Calls -> Call History -> Calling / Incoming / Active Call
      ├── Contacts -> Search Username -> Profile -> Start Chat
      ├── Settings -> Account | Privacy | Notifications | Appearance | Devices
      └── Admin (role admin only) -> Users | User Detail | Audit Log
```

**Navigasi utama versi awal:** bottom navigation 4 tab **Chats, Calls, Contacts, Settings**. Admin berada di Settings atau menu tersendiri yang hanya muncul bila authorization berhasil. Bila Calling belum dirilis, tab Calls tetap disembunyikan, bukan tampil sebagai fitur rusak.

## 5.2 Perilaku back dan deep links

- Tombol Back dari detail chat kembali ke daftar tanpa menghapus draft.
- Back dari media viewer kembali ke posisi scroll chat terakhir.
- Back dari active call tidak mengakhiri panggilan: tampil mini-call/ongoing notification.
- Notifikasi pesan melakukan deep link ke chat setelah autentikasi dan unlock; tidak membuka konten sensitif di layar terkunci.
- Navigasi dari notifikasi yang sudah tidak relevan (pesan ditarik/hapus, chat diblokir) menampilkan fallback ke daftar chat.
- Ketika logout, semua deep link tertunda yang mengarah ke konten privat dibatalkan.

# 6. Sistem desain UI: Midnight Blue

## 6.1 Prinsip desain

- **Calm & clear:** kontras tinggi, hierarchy informasi lugas, indikator status mudah dibedakan.
- **Blue = action:** biru kuat dipakai untuk CTA, chat bubble outgoing, pilihan terpilih, bukan seluruh permukaan.
- **Privacy by default:** data sensitif disamarkan di preview, notifikasi, recents screenshot jika user mengaktifkan pengamanan.
- **Stateful first:** semua operasi punya loading, pending, success, error, dan retry yang nyata.
- **Accessibility:** ukuran target sentuh minimal 48x48 logical px, dukungan font scale, screen reader, warna bukan satu-satunya sinyal.

## 6.2 Design tokens

| Token | Dark Mode | Light Mode | Penggunaan |
|---|---|---|---|
| `bg.primary` | `#080D18` | `#F6F9FF` | dasar layar |
| `bg.surface` | `#111B2C` | `#FFFFFF` | kartu/dialog |
| `bg.raised` | `#172337` | `#E9F0FA` | search bar/composer |
| `brand.primary` | `#2563EB` | `#2563EB` | CTA/outgoing |
| `brand.soft` | `#60A5FA` | `#1D4ED8` | icon/link |
| `text.primary` | `#F8FAFC` | `#0F172A` | judul/pesan |
| `text.secondary` | `#94A3B8` | `#64748B` | metadata |
| `border` | `#26354A` | `#DCE5F2` | divider |
| `bubble.incoming` | `#172337` | `#E8EFFA` | chat incoming |
| `bubble.outgoing` | `#1D4ED8` | `#2563EB` | chat outgoing |
| `status.error` | `#F87171` | `#B91C1C` | error |
| `status.success` | `#34D399` | `#047857` | sukses |
| `focus.ring` | `#93C5FD` | `#1D4ED8` | fokus keyboard |

**Kontras:** kombinasi warna wajib diuji terhadap WCAG 2.2 AA (teks umum minimal 4.5:1, teks besar 3:1), termasuk teks di bubble biru dan disabled states. Nilai token dapat dikoreksi jika kontras gagal.

## 6.3 Tipografi, ukuran, dan spacing

- Typeface: **Inter** atau font sistem Android yang teruji legibilitasnya; fallback untuk glyph non-Latin dan emoji.
- Display 28/34 semibold; screen title 22/28 semibold; section 18/24 medium; body 15-16/22; caption 12-13/18. Jangan bergantung pada hardcoded pixel.
- Spacing system: 4, 8, 12, 16, 20, 24, 32 dp; corner radius: 8 (input), 12 (cards), 16 (dialogs), 18-22 (bubble), pill untuk avatar/badge.
- Transition 150-250 ms; adaptif terhadap pengaturan reduce motion.
- Icon stroke konsisten 1.75-2; tidak memakai warna saja untuk unread, error atau disabled.

## 6.4 Theme behavior

- Pengaturan: **Follow System** (default), **Dark**, **Light**; disimpan lokal dan disinkron opsional ke `user_preferences`.
- Saat tema berubah, tidak kehilangan scroll position, draft, playback state, atau ongoing call.
- Status/navigation bar mengikuti brightness tema, splash tidak menjadi putih menyilaukan saat dark mode.
- Gambar, thumbnail dan emoji tidak dibalik warnanya.
- Keyboard dan bottom sheet mengikuti tema aktif.

## 6.5 Perangkat, ukuran layar, dan accessibility

- Mobile portrait baseline 360-412 dp; UI tetap layak pada 320 dp, font scale 1.3x dan 2x, landscape, layar foldable.
- Hindari fixed-height form agar keyboard tidak menutupi CTA.
- Screen reader label: nama chat, unread count, pengiriman status, tombol rekam dan status mikrofon.
- Avatar dengan initials fallback; skeleton loaders tidak membuat layout bergeser berlebihan.
- Haptics hanya untuk tindakan bermakna (send, hold, call connected) dan dapat dimatikan.

# 7. Spesifikasi layar detail dan UX copy

**Konvensi layar:** setiap layar harus memiliki: default state; empty; loading; network offline; permission denied jika relevan; error; success; accessibility labels.

## UI-01 Splash / Bootstrap

**Komponen:** logo Adoetz Chat, background tema, spinner kecil setelah 300 ms, versi app pada footer. **Proses:** cek config, validasi keberadaan session, status blokir, local E2EE identity, skema cache, deep link tertunda. **Error:** koneksi putus -> lanjut ke cached inbox read-only jika session/keys valid; critical migration failed -> recovery UI dengan opsi retry dan export diagnostics tanpa pesan. **Jangan:** splash yang berputar tanpa batas. **Timeout UX:** setelah sekitar 8 detik tawarkan Retry / Offline Mode.

## UI-02 Welcome

**Komponen:** logo, headline 'Pesan privat, tetap simpel', primary Sign In, secondary Create Account, petunjuk 'Registration by invitation only', privacy explainer singkat, pilihan theme. **Kondisi:** daftar dibatasi invitation; jangan menjanjikan anonymitas total.

## UI-03 Sign Up

**Form:** invitation code, username, email, password, confirm password; checkbox setuju Terms/Privacy. Username 3-24 karakter, lowercase alfanumerik dan underscore sebagai **PROPOSED**; username tampil tanpa case-sensitive, canonical normalized; reserved names (`admin`, `support`, `system`, ...). Email divalidasi format, dinormalisasi aman sesuai semantik provider; jangan menerapkan transformasi email yang menyalahi canonicalization provider. Password minimal 12 karakter **PROPOSED**, memungkinkan passphrase panjang, paste, autofill, show/hide, tanpa aturan komposisi berlebihan. Indikator kekuatan bersifat edukatif. Tombol disabled saat invalid/submit.

**UX validasi:** check username asynchronous dengan debounce, namun hasil check bukan jaminan sampai transaksi commit. Error spesifik untuk format; error generik untuk enumeration-sensitive context. Loading indeterminate dan progress langkah registrasi; jangan membuat akun ganda akibat double tap. Berhasil -> 'Account created' -> local identity creation -> inbox. Jika identity key generation gagal, arahkan ke retry aman; jangan membiarkan akun tampak bisa chat tanpa E2EE.

**Tanpa email verification:** user langsung login. Berikan label 'Email belum diverifikasi; pemulihan via email tidak dijamin' dan fasilitas mengubah email. Password recovery via email **ditahan** hingga ada kanal recovery yang terbukti dimiliki pengguna. Jangan menyamakan "Confirm Email OFF" dengan bukti kepemilikan alamat.

## UI-04 Sign In

**Komponen:** satu field 'Email or username', password, show/hide, Remember this device, Sign In. Tekan Enter pada keyboard submit. Login username diproses server-side secara aman; jangan mengekspose mapping username->email ke client. **Error auth:** 'Username/email atau password tidak sesuai'; untuk rate-limit tampil cooldown; offline -> penjelasan tidak bisa login baru tanpa koneksi. Tidak mengumumkan akun terdaftar/tidak melalui pesan error.

## UI-05 Invitation Error

Status: kode salah/expired/already used, undangan dibatalkan, permintaan terlalu sering, error sementara. CTA: 'Try another code' dan 'Contact administrator' tanpa membocorkan apakah email orang lain ada di sistem.

## UI-06 First-Run Permissions

Prompts permission **contextual** bukan memaksa semua saat launching: notifications saat user siap memakai chat; mic saat voice note/call pertama; kamera saat video; photo picker melalui API sistem; biometrik saat mengaktifkan App Lock. Jika denied, fungsi lain tetap berjalan dengan fallback dan tombol Open Settings.

## UI-07 Chats List

**Header:** 'Chats', search action, compose icon, avatar user. **Body:** searchable chats (search local decrypted metadata only), avatar, display name/username, last message snippet (local decrypted cache), timestamp, unread badge, pinned marker, mute icon, connection banner. Long press -> Pin, Mute, Archive (P1), Delete local chat (konfirmasi). **Empty:** illustration abstrak, 'Belum ada percakapan', CTA Find People. **Offline:** banner minimal 'Offline • messages will send when connected', cached list usable. **Privacy:** optional 'Hide previews' in app switcher/notification; list message snippet encrypted locally.

## UI-08 Contact Search

Username exact/prefix search, display name/avatar hanya jika user mengizinkan discoverability. Search dengan debounce dan pagination; batasi request serta query yang mencurigakan. Result -> profile preview -> Start chat. **No result:** 'No matching username'. **Blocked/hidden:** jangan menampilkan keberadaan identitas tersembunyi. Keamanan anti-enumeration penting.

## UI-09 Contact Profile

Avatar, display name, `@username`, bio, verified safety-number status, actions Chat, Voice Call, Video Call, Block, Report. Email dan last active tidak ditampilkan tanpa consent. Trust warning bila identity key berubah; Call/Send dapat ditahan sampai user mengonfirmasi kunci baru sesuai pengaturan keamanan.

## UI-10 Chat Detail

**Top bar:** back, avatar, name, state (online/last active hanya jika opt-in), voice/video icons, menu. **Conversation:** date separators, message bubbles, reactions, status icons, encrypted attachment tiles, reply quote, pinned unread separator, load older; pull-to-retry lebih tepat pada failed fetch daripada selalu pull-to-refresh. **Composer:** text multiline, emoji, attachment, voice hold/tap, send action, reply preview/dismiss. Keyboard submit vs newline jelas. Draft autosave lokal encrypted, tidak sync ke server pada v1. **Media:** incoming thumbnail hanya dibuat setelah decrypt lokal. **Gesture:** long press message opens actions; swipe right reply dengan haptic; message actions accessible via long press and explicit menu.

**Message status:** `queued` (jam), `encrypting`, `sending` (spinner), `sent` (server accepted), `delivered` (ack perangkat penerima), `read` (ack baca jika enabled), `failed` (retry). Tidak menyebut `sent` sebagai sudah dibaca. Read receipts opt-out harus dihormati; group receipts bukan fitur awal.

## UI-11 Attachment Picker / Preview

Foto/video via system picker, file via SAF/system file picker, preflight file size/type, optional compression/trim, preview, caption, remove, cancel. Encrypt di device dan upload private object; progress per file, pause/cancel bila memungkinkan, retry upload resumable jika dukungan dipastikan. Media download lazy dan Wi-Fi only option; tampil error jika storage penuh, key tidak tersedia, file tidak ditemukan, file terhapus, atau akses foto dicabut.

## UI-12 Voice Note

Press-and-hold record / swipe cancel / lock-to-record sebagai **P1**. Indikator durasi, cancel, playback sebelum send, pause-resume jika library aman. Izin mikrofon dikonfirmasi saat interaksi. Audio direkam sementara lokal dengan proteksi, dienkripsi sebelum upload, file plaintext sementara dihapus best-effort saat selesai/cancel. Incoming voice note: play/pause, speed 1x/1.5x/2x, scrub yang accessible, headset switch. Hindari autoplay.

## UI-13 Chat Info / Privacy

Avatar, display name, username, verify safety number QR/fingerprint, mute, wallpaper (P2), shared media, clear local cache, block/report, disappearing messages (P2). Tampilkan peringatan bahwa perubahan identity key memerlukan verifikasi ulang.

## UI-14 Calls History

Tab Calls list incoming/outgoing/missed/declined dengan timestamp, duration, avatar, callback, per-call retry; empty 'Belum ada panggilan'. Call logs menyimpan metadata minimal tanpa rekaman audio. User dapat hapus call log lokal, kebijakan server ditetapkan terpisah.

## UI-15 Outgoing Call

Avatar, nama, call state `connecting`, `ringing`, `reconnecting`, `busy`, `no answer`, `failed`. Tombol cancel prominent, mic/speaker pre-call settings. Timeout **PROPOSED** 30-45 detik tanpa jawaban. UI harus tidak mengklaim ringing sampai sinyal tujuan diterima; jika server push accepted saja, tampil 'Calling…'.

## UI-16 Incoming Call

Caller name/avatar aman, Answer/Decline; lock-screen presentation menggunakan Android calling APIs dan notification integration yang mematuhi izin/device policy. Fallback heads-up notification jika full-screen intent tidak diizinkan. Answer membuka app, menguji authentication/session, mic permission, peer/call validity; jika panggilan sudah expired -> 'Call ended'. Tolak duplicate incoming events berdasarkan `call_id`.

## UI-17 Active Voice / Video Call

Voice: nama, duration, network quality label, mute, speaker/Bluetooth, switch video, end. Video: remote fullscreen, local picture-in-picture inset, front/back camera, mute mic, camera off, end, permission fallback. Incoming background/ongoing call notification. Saat jaringan drop: 'Reconnecting…' selama grace period lalu terminate dengan alasan jelas; update layar tidak menciptakan dua call session. Harus ada indikator mic/camera yang aktif, consistent dengan Android indicator.

## UI-18 Settings

Profil, Account, Privacy & Security, Notifications, Appearance, Storage & Data, About/Version, Admin Panel (admin only), Logout. Row dengan ikon, label, deskripsi pendek bila perlu. Logout dibedakan dari 'Delete Account'; destructive actions memerlukan konfirmasi.

## UI-19 Appearance

Pilihan System, Dark, Light; preview chat bubbles, accent fixed Electric Blue untuk v1; font sizing mengikuti OS. Perubahan langsung terlihat dan disimpan.

## UI-20 Privacy & Security

App Lock biometric/PIN; hide notification previews; read receipts; typing indicators; discoverability; block list; safety number verification; device identity; sign out other sessions (tergantung arsitektur); E2EE education. Detail privasi menyatakan metadata (misal akun berkomunikasi dan waktu) masih diproses server untuk layanan.

## UI-21 My Account / Devices

Edit avatar/display name/bio/username (jika kebijakan allow); ubah password setelah re-auth; email change hanya dengan peringatan verifikasi; device registration list (model perangkat yang wajar ditampilkan), revoke; delete own account (jika diaktifkan). **Single-E2EE-device:** sign-in baru di device lain memicu flow 'Replace active device' atau key transfer yang diautentikasi; jangan diam-diam mengganti identity key.

## UI-22 Admin Dashboard

Ringkasan total/active/suspended users, pending invites, recent administrative actions; navigasi Users, Invites, Audit. Tidak ada view isi chat. Pencarian username/email/UUID, server-side paginated 20-50 rows, filter role/status, loading skeleton, export audited jika diizinkan. Semua operasi berasal dari Edge Function berotorisasi.

## UI-23 Admin User Detail

Header identitas akun, username/email, role, status, created-at, last signed-in bila diperlukan; tindakan Suspend/Unsuspend, Force Password Reset, Revoke Sessions, Change Role (guarded), Delete. Action destructive menggunakan dialog dua langkah dengan alasan dan reauthentication admin untuk risiko tinggi. Password baru tidak pernah muncul di audit log. UI harus melarang self-delete/last-admin removal dan status konflik update.

## UI-24 Admin Invites & Audit

Invite: generate random one-time code, max uses, expiry, optional recipient/label, revoke, copy safely. Penyimpanan token hash, bukan token plaintext. Audit: actor, action, target, timestamp, reason, result, correlation ID, tanpa credential/pesan/decrypted content. Paginasi, filter, pembatasan akses.

## UI-25 Universal Errors / Maintenance

**Screen states wajib**: full-screen fatal (database migration corruption), blocked/suspended account, session expired, maintenance, required update (hanya jika benar-benar inkompatibel), offline mode, failed decryption, storage quota, permission denied. Pesan error manusiawi dan actionable. Tombol 'Copy diagnostic code' tidak menyalin token, PII, atau plaintext.

# 8. Detail alur end-to-end

## FL-01 Register invite-only

1. User membuka welcome -> Create Account.
2. Masukkan invite code; server mengecek token hash, TTL, status dan rate limit.
3. Isi username/email/password; validasi sinkron + server check.
4. Registrasi melalui **server-gated path** yang tidak dapat dilewati dengan memanggil endpoint Auth publik secara langsung. Pengembangan harus memilih kontrol Auth/hook/provider yang tervalidasi dan didukung.
5. Selesaikan transaksi profil + role default `user`; invite dikonsumsi atomically/idempotently.
6. Generate E2EE identity dan prekeys di perangkat; upload **public** material yang tervalidasi.
7. User masuk inbox; tampil welcome tooltip singkat.
8. Jika pembuatan profil/keys gagal, masuk state pending-setup dan retry terkontrol, bukan akun parsial tanpa hak yang salah.

## FL-02 Login via email / username

1. Input identifier/password -> server rate limit per IP/device/account hash.
2. Email menggunakan Auth password flow; username dipetakan server-side, tidak membocorkan email ke search API.
3. Setelah sesi didapat, fetch profile/status/role dan perangkat E2EE.
4. Device belum terdaftar -> enforce replace/migration policy.
5. Login berhasil -> inbox; salah -> pesan error generik, bukan enumeration.
6. Banned/suspended -> kunci kemampuan mengakses private resources segera melalui policy dan server-side checks; sesi yang mungkin masih hidup tidak memberikan akses operasional.

## FL-03 Logout

1. User pilih Logout, dialog opsional memperingatkan draft/outbox belum terkirim dan kunci lokal.
2. Revoke refresh token/session sesuai cakupan pilihan (device ini/all sessions), reset in-memory decrypted content.
3. Hentikan subscriptions/call/FCM mapping; hapus sensitive local cache berdasarkan kebijakan.
4. E2EE private key diperlakukan eksplisit: **sign out saja** tidak boleh otomatis menghapus kunci bila tidak ada recovery, tapi app lock/auth wajib sebelum pemakaiannya kembali.
5. Redirect welcome, blocked back navigation, hapus notification sensitive cache.

## FL-04 Send text DM

1. Compose -> validasi penerima, blokir/status, recipient identity/prekeys.
2. Generate `client_message_id` UUID; simpan outbox lokal durable.
3. Enkripsi di device, simpan ciphertext di outbox, lakukan send idempotent ke server.
4. Server validasi membership + row policy + deduplication, menerima ciphertext, assign `server_message_id` + timestamp.
5. Realtime private-channel notify, FCM metadata-only bila recipient background.
6. Device tujuan sync gap/history, decrypt lokal, ack delivered saat benar-benar tersimpan di device, read bila dibuka dan setting mengizinkan.
7. Sender meng-update state; retry tidak menggandakan pesan.

## FL-05 Send attachment

1. File picker -> validasi ukuran/type/quota, preview lokal.
2. Client generate random content encryption key + nonce; enkripsi file streaming/chunked sesuai desain crypto library.
3. Upload blob ciphertext ke private bucket; simpan metadata terenkripsi + wrapped key di message E2EE.
4. Jika gagal upload, pesan tak dipublikasi sebagai berhasil; tampil Retry/Cancel; orphan object dibersihkan periodic dengan TTL.
5. Penerima mengambil ciphertext memakai storage authorization, verifikasi hash/tag, decrypt lokal; key dan MIME asli tidak diletakkan di metadata public.

## FL-06 Admin reset password

1. Admin buka user detail -> Force Reset -> confirm reason + admin reauth.
2. Edge Function verifikasi JWT, admin status terbaru, target restriction, rate limit.
3. Backend set password temporary/reset state menggunakan privileged Auth API; beritahu user melalui kanal yang aman dan terpisah.
4. User dipaksa mengganti password di login berikutnya; revoke session yang harus dibatalkan, perhatikan access JWT belum tentu langsung invalid.
5. Audit action dicatat tanpa password. **E2EE private keys tidak dipindahkan ke admin atau diekspor oleh server.**

## FL-07 Incoming call

1. Caller request call ID one-time, server validasi kedua user, block, busy state, TTL.
2. Signaling lewat authenticated private channel dan FCM push notification berprioritas sesuai kebijakan.
3. Receiver melihat incoming UI/notifikasi bila platform mengizinkan; accept/decline dikirim idempotently.
4. WebRTC handshake dengan TURN fallback, identitas media terikat pada peer authenticated, DTLS-SRTP aktif.
5. Call active; handle ICE restart, network change, participant hangup, background, timeout, stale push.
6. End call -> release tracks, stop notification, log only minimal metadata, bersihkan signaling sensitif.

# 9. Messaging rules dan data semantics

## 9.1 Pesan dan event

- Setiap item mempunyai `client_message_id` dan `server_message_id`, `conversation_id`, `sender_id`, `ciphertext`, `protocol_version`, `created_at_server`, `edited_at`, `deleted_at`, `message_type`, `envelope_metadata` yang minimal.
- Ordering menggunakan cursor `(server_created_at, message_id)` untuk determinisme; jangan mengandalkan jam perangkat.
- **Sent:** commit server berhasil. **Delivered:** receiver device menyimpan/decrypt dengan sukses sesuai protokol receipts yang terenkripsi. **Read:** chat dibuka/posisi terbaca & read receipts enabled.
- Typing/presence adalah ephemeral dengan TTL; tidak menulis database di setiap keystroke.
- Edits dan delete-for-everyone dipresentasikan sebagai **E2EE control events** (atau tombstone yang aman), bukan edit plaintext di database.
- P1 reaction, reply metadata dan forwarding harus menjaga kerahasiaan; referensi pesan sebaiknya berupa ID opaque dengan otorisasi membership.
- Stop duplicate sends akibat retry, tap ganda, reconnect, notification duplication, atau response timeout.
- Delete for me menghapus local view saja; delete for everyone adalah best-effort event yang dapat gagal di perangkat offline dan tidak menghapus salinan penerima.

## 9.2 Receipt & conversation behavior

- Batas pagination 30-50 item **PROPOSED**; lazy render list, reverse scroll terkontrol.
- Unread count authoritative/derived server + client reconciliation; jangan menghitung ganda akibat rerender.
- Draf tersimpan lokal, tidak membocorkan plaintext ke analytics.
- System message (user added/identity changed/call missed) bukan konten palsu yang disisipkan sebagai user.
- Blokir: user A yang memblokir B tidak menerima chat/call baru dari B; tampilan untuk B tidak membocorkan informasi personal yang tidak perlu. Existing history tetap lokal sesuai pengaturan.
- Attachment max size dan supported formats diputuskan setelah quota test. Usulan beta: image 15 MB, video 100 MB, document 25 MB, voice note 10 menit, **dapat berubah** sesuai plan dan kemampuan Storage/biaya.

# 10. E2EE, identitas perangkat, dan batas privasi

## 10.1 Threat model ringkas

**Dilindungi dari:** operator backend penasaran, query database bocor, read terhadap object storage, jaringan publik penyadap, pencurian token API publik, sebagian kompromi server yang tidak menguasai klien.

**Tidak otomatis dilindungi dari:** perangkat yang dibajak/malware, screenshot, korban membagikan konten, key substitution jika tidak ada verifikasi, traffic analysis, kompromi update APK/signing key, notifikasi yang sengaja mengandung teks plaintext.

## 10.2 Kewajiban implementasi

- Gunakan implementasi E2EE yang ditinjau dan dipelihara, misalnya keluarga **Signal Protocol** dengan handshake dan Double Ratchet sesuai dukungan library terpilih; hindari protokol/algoritma buatan sendiri.
- Evaluasi *native Android bindings via Flutter FFI/platform channels* bila library Dart murni tidak memenuhi keamanan/maintenance. Buat **security proof-of-concept** sebelum mengunci jadwal v1.
- Private identity keys dan state ratchet disimpan encrypted-at-rest, dibungkus Android Keystore / secure key wrapping; hindari private key di SharedPreferences/log/backups OS tanpa proteksi.
- Public key/prekey directory di server; signed prekeys, one-time prekeys atomic consume, rotasi/replenishment, replay protection.
- Show fingerprints/safety numbers; warn on identity key change; konfigurasi kebijakan send-after-key-change.
- Protocol versioning, backwards compatibility, ratchet state atomic commit dengan outbox/inbox agar crash tidak merusak dekripsi atau menggunakan nonce/key state yang salah.
- Attachments menggunakan AEAD yang layak; nonce uniqueness dan authentication tag diperiksa; file key dibungkus lewat pesan E2EE.
- Panggilan WebRTC memakai transport encryption, **plus peer authentication/key binding** supaya signaling server tidak dapat diam-diam melakukan man-in-the-middle.
- Audit dependency, static analysis, review independent sebelum klaim keamanan produksi.

## 10.3 Recovery dan reset akun

- Password Supabase **bukan** E2EE private key. Reset password tidak boleh mengungkap riwayat chat lama.
- Single-device v1: jika kehilangan device tanpa backup, histori lama mungkin tidak dapat didekripsi; tampilkan warning sebelum mengganti perangkat.
- Saat reinstall, key rotation dianggap perubahan identitas: kontak melihat security alert; key archive/backup terenkripsi baru ditambahkan P2 setelah security design.
- Jika ada local state tetapi kunci rusak, client menawarkan Retry/Support diagnostics, tidak silent-recreate identity lalu berpura-pura chat lama terbaca.
- Admin tidak boleh memiliki mekanisme 'master key' tersembunyi.

## 10.4 Kebijakan metadata dan notifikasi

- Backend masih bisa mengamati *siapa berbicara dengan siapa*, waktu, ukuran ciphertext, status akun, IP saat terhubung, token push, dan catatan panggilan kecuali ada desain metadata-hiding khusus.
- FCM data payload berisi ID opaque dan jenis peristiwa minimal; **tidak boleh** menyertakan plaintext pesan maupun key.
- Android notification preview default: 'Pesan baru' / nama pengirim hanya jika consent; plaintext preview yang dihasilkan lokal perlu desain aman dan tidak selalu tersedia saat app mati.
- Screenshot protection (FLAG_SECURE) adalah pilihan user atau untuk layar sensitif; tidak menjanjikan anti-rekam absolut.

# 11. Voice/video calling specification

## 11.1 Call state machine

```text
idle -> initiating -> calling -> ringing -> connecting -> connected
                           |         |           |
                           v         v           v
                         failed    declined   reconnecting -> connected
                           |         |           |
                           +---------+-----------+----> ended
```

- Backend authoritative untuk `call_id`, participants, TTL, busy/reject/end, validasi anti spoofing.
- ICE/STUN/TURN fallback harus diuji lintas NAT carrier; credential TURN singkat dan terotentikasi; jangan hardcode TURN secret dalam APK.
- Akhiri panggilan jika remote disconnected beyond grace period (contoh 20-30 s **PROPOSED**) dan nyatakan reason.
- Incoming push bisa terlambat, duplicate, atau tiba setelah call berakhir; receiver selalu cek TTL/status sebelum Answer.
- Dua call bersamaan: beri busy atau mekanisme call waiting yang eksplisit (default beta = busy).
- Saat user force-stop, Doze ekstrem, izin full-screen ditolak atau OEM killing app: fallback behavior dan panduan settings, bukan janji mustahil.
- Telepon GSM/VoIP lain masuk -> audio focus dan lifecycle diatur; default pause/mute atau end menurut callback platform.
- Ketika bluetooth/headset tersambung/terlepas, routing audio diperbarui dan dikomunikasikan ke pengguna.

## 11.2 Network adaptive UX

- Latency/jitter/loss diamati secara on-device; UI hanya menampilkan Poor / Fair / Good, bukan metrik teknis berlebihan.
- Video bitrate/resolution adaptif, audio diprioritaskan saat bandwidth rendah; tombol 'Switch to voice'.
- Camera permission denied -> voice call tetap bisa berlangsung.
- Mic permission denied -> tidak bisa call two-way; jelaskan permission dan Open Settings.
- Front/back camera switch harus tidak memutus panggilan. Media track stop saat end dan app lifecycle.

# 12. Push notifications dan background execution

- Gunakan FCM HTTP v1 dari Edge Function/secure worker; token perangkat disimpan server-side, dapat dirotasi dan dicabut.
- **Chat notifications:** push sebagai *wake-up hint*; kebenaran data berasal dari sync inbox ketika app aktif. Realtime saja tidak menjamin notifikasi background.
- **Call notifications:** priority tinggi untuk event time-sensitive, batasi spam dan pastikan notifikasi yang terlihat user sesuai kebijakan FCM.
- Android 13+ permission notifications diminta kontekstual; jika ditolak, app harus tetap usable saat dibuka.
- Android 14+ full-screen call UI memerlukan eligibility dan permission behavior yang harus dicek saat runtime; fallback heads-up/notification.
- Force-stop, network unreachable, battery optimization, notification blocked, token expired => delivery tidak dijamin. Tampilkan in-app diagnostic 'Notifications disabled' bila bisa dideteksi.
- FCM payload dedup by event ID, TTL call singkat, collapse key hanya untuk event yang layak digabung; **jangan collapse pesan unik** sehingga kehilangan indikasi pesan.
- Jangan mengirim plaintext chat lewat Firebase; local notification preview setelah decrypt hanya bila app memiliki akses aman dan user memilihnya.

# 13. Offline-first, sync, dan konflik

## 13.1 Data lokal

- Database lokal encrypted-at-rest untuk index chat, message ciphertext, read pointers, outbox, cached decrypted presentation (bila diperlukan dan dilindungi), key state.
- Outbox durable dengan retry exponential backoff + jitter; tidak retry infinite pada auth denied, user blocked, quota, message malformed.
- Pending uploads resume/retry sesuai kemampuan platform; cancel cleans local temporary data.
- App memproses reconnect sebagai **delta sync** berdasarkan cursor server, bukan menganggap semua event Realtime pasti diterima.
- Sync memakai snapshot + change cursor; state merge deterministik untuk edit/delete/reactions; unread counts direkonsiliasi.

## 13.2 Konflik prioritas

- Server commit timestamp untuk order; local pending tetap tampil optimistically dengan placeholder.
- Saat delete-for-everyone tiba sebelum original pesan, simpan tombstone supaya pesan tidak muncul kembali saat sync.
- Saat receipt datang sebelum message event, simpan pending receipt / id lookup lalu reconcile.
- Saat role/status user berubah sementara offline, semua operasi di server harus melakukan authorization terbaru.
- Clock skew perangkat tidak boleh menyebabkan pesan hilang/tidak urut permanen.

# 14. Data model konseptual (Supabase PostgreSQL)

**Catatan:** skema berikut adalah model produk, bukan SQL migration final. Semua kolom dan index perlu finalisasi lewat migration yang diuji.

| Table / schema | Field inti dan fungsi | Catatan security |
|---|---|---|
| `auth.users` | Provider-maintained auth identity, email/password hash/session | Bukan tabel CRUD Flutter biasa |
| `profiles` | `user_id`, `username_normalized` UNIQUE, `display_name`, `avatar_path`, `bio`, `discoverable`, `created_at` | Read minimal untuk search; write sendiri |
| `user_roles` | `user_id`, `role`, `created_at` | Write privileged; default user via trusted path |
| `account_status` | `user_id`, `status`, `suspended_at`, `reason_code` | Restricted; enforcement dalam RLS/server |
| `invitations` | `id`, `token_hash`, `status`, `max_uses`, `expires_at`, `created_by` | Never leak unhashed invite; atomic redemption |
| `conversations` | `id`, `kind`, `created_at`, `last_event_at` | Membership authorization |
| `conversation_members` | `conversation_id`, `user_id`, `joined_at`, `state`, `last_read_cursor` | RLS scoped participant |
| `messages` | `id`, `client_message_id`, `conversation_id`, `sender_id`, `ciphertext`, `protocol_version`, `server_created_at` | Ciphertext only, idempotency key unique |
| `message_receipts` | `message_id`, `recipient_id`, `type`, `created_at` | Membership + receipts privacy |
| `attachment_objects` | `id`, `owner_id`, `ciphertext_path`, `size_bytes`, `upload_state`, `expires_at` | Private storage, signed access rules |
| `devices` | `id`, `user_id`, `public_identity_key`, `status`, `last_seen` | Single-device E2EE policy v1 |
| `device_prekeys` | `device_id`, `key_id`, `public_key`, `signed_metadata`, `consumed_at` | Atomic consume / replenishment |
| `push_tokens` | `device_id`, `token_encrypted_or_protected`, `updated_at` | Never globally queryable |
| `calls` | `id`, `initiator_id`, `receiver_id`, `status`, `started_at`, `ended_at`, `expires_at` | Caller/receiver only; minimal metadata |
| `call_signaling_events` | `call_id`, `sender_id`, `payload`, `expires_at` | Private channel, short TTL, purge |
| `blocked_users` | `blocker_id`, `blocked_id`, `created_at` | Query minimal to avoid exposing block list |
| `user_preferences` | `user_id`, `theme`, `read_receipts`, `notification_privacy` | Scoped own account |
| `admin_audit_logs` | `actor_id`, `target_id`, `action`, `reason`, `result`, `request_id`, `created_at` | Append-only service-side |
| `outbound_jobs` | `id`, `event_type`, `recipient_device_id`, `status`, `retry_count` | Durable notification dispatch |

**Indices:** unique casefold username; unique `(sender_id, client_message_id)` untuk dedup; cursor `(conversation_id, server_created_at, id)`; `(user_id, status)` device; `(expires_at)` cleanup tables; keys sesuai query plan.

**Jangan mencampur** secret/service key, reset token, recovery key, atau password sementara dalam public tables. Pertimbangkan schema `private` tak terekspos untuk invites, auth helpers, outbound jobs, dan audit data tertentu.

# 15. RLS, akses realtime/storage, dan trust boundaries

- RLS aktif pada semua table exposed; periksa GRANT schema/Data API, bukan hanya policy.
- Contoh kebijakan konseptual: user `SELECT` messages hanya jika ia anggota percakapan aktif; `INSERT` pesan hanya jika `sender_id = auth.uid()` dan sender anggota, akun tidak suspended, recipient relation belum diblokir, payload cocok batas ukuran/protocol.
- Update `profiles`: ownership pada `USING` **dan** `WITH CHECK`; update biasanya memerlukan SELECT yang sesuai.
- Tabel role/audit/invite privileged tidak menyediakan insert/update langsung untuk client biasa; fungsi privileged dengan cek admin server-side.
- `app_metadata` dapat menjadi sumber klaim otorisasi, bukan `user_metadata` yang editable oleh user; perubahan role perlu mempertimbangkan JWT stale.
- Realtime channel private dengan authorization berdasarkan membership; jangan subscribe channel berdasarkan ID percakapan saja tanpa RLS.
- Supabase Realtime **Broadcast** diprioritaskan untuk scalable new-event signals; durable history tetap PostgreSQL. Presence ephemeral, Postgres Changes boleh dipakai untuk prototipe kecil jika constraints disadari.
- Storage buckets private; object path random non-guessable; authorization ownership/membership diverifikasi dalam policy atau Edge Function; signed URLs short TTL jika dipakai; semuanya tetap ciphertext.
- No `service_role`/secret keys, Firebase service account, TURN secret, release keystore/password di Flutter APK atau Git repository.
- Admin deletion tidak selalu langsung mematikan access JWT yang sudah issued; revoke refresh sessions, enforce account-status table pada operasi sensitif, refresh channel claims, dan TTL pendek berdasarkan tradeoff.
- Uji policy dengan direct REST API menggunakan client role `user`, bukan hanya UI flow.

# 16. Edge Functions / server contracts

| Function (proposed) | Input inti | Auth / aturan | Response / retry |
|---|---|---|---|
| `redeem-invite-register` | invite, username, email, password, idempotency | Public rate limited; verify invite atomically | user/session atau pending-setup; no leak |
| `login-identifier` | username/email, password, device marker | TLS, abuse controls, no password logs | session, generic errors |
| `username-availability` | username candidate | public/limited, throttle, anti-enumeration | available/invalid with caveats |
| `create-chat` | recipient user ID, request ID | authenticated, not blocked, dedup | conversation ID |
| `issue-attachment-upload` | conversation, file size, mime hint | membership/quota | private upload grant |
| `dispatch-push` | event ID, recipient device | server-generated only | queued; durable retry |
| `initiate-call` | peer ID, request ID | not blocked; both allowed; busy limit | call ID / expires_at |
| `call-action` | call ID, accept/decline/end | participant-only; state checked | authoritative state |
| `admin-list-users` | filter, cursor | live admin check | redacted paginated data |
| `admin-user-action` | target, action, reason, request ID | live admin + step-up auth | result + audit ID |
| `admin-invitations` | create/revoke/list | live admin | codes on create only |
| `register-device-key` | device/public key/prekeys | auth + protocol validation | registration state |
| `get-prekey-bundle` | recipient ID/device | authorized + rate limit | signed bundle public material |

**Common response contract:** `request_id`, `success`, `data`, `error.code`, `error.message`, `retryable`, optional `retry_after_seconds`. Status codes obey semantic 400/401/403/404/409/422/429/5xx. Idempotency key on all mutation endpoints. Server validates all fields independent of Flutter form.

# 17. Error, edge-case, dan recovery matrix

**Standar setiap error:** pesan singkat manusiawi, kode diagnosa, apakah aman retry, siapa yang dapat memperbaiki, pencegahan duplikasi, dan risiko kehilangan data. Jangan menampilkan stack trace atau server secrets ke UI.

| ID | Skenario kegagalan | Expected UX | Recovery / engineering |
|---|---|---|---|
| ERR-01 | Internet mati saat startup | Cached inbox, banner Offline | Retry foreground, jangan clear session |
| ERR-02 | Internet mati saat send | Bubble `Queued`, timestamp lokal | Durable outbox + retry idempotent |
| ERR-03 | Server commit sukses tapi response timeout | Tetap `Sending` sementara, bukan duplicate | Query by `client_message_id`; reconciliation |
| ERR-04 | User menekan Send berkali-kali | Hanya satu bubble transaksi | Disable transient / dedup UUID |
| ERR-05 | Realtime disconnect 5 menit | Banner reconnect singkat; history tidak hilang | Rejoin + cursor catch-up sync |
| ERR-06 | Event Realtime tiba dua kali | Pesan tidak tampil ganda | Upsert by server message ID |
| ERR-07 | Receipt datang sebelum message | Tidak error/kacau status | Deferred receipt reconciliation |
| ERR-08 | Jam HP salah jauh | Tetap order benar | Server timestamp & stable cursor |
| ERR-09 | User online di HP lain tanpa migration | Dialog keamanan perangkat | Block second E2EE device / verified migration |
| ERR-10 | Ratchet state corrupted | 'Pesan tidak dapat didekripsi' + code | Quarantine affected message; no silent key regeneration |
| ERR-11 | Penerima mengganti identity key | Security alert sebelum percakapan lanjut | Verify fingerprint; re-establish secure session |
| ERR-12 | Prekey habis atau unavailable | Message pending 'Secure setup pending' | Replenish keys; retry limited |
| ERR-13 | Pesan ciphertext dimodifikasi | Dekripsi ditolak, UI gagal aman | AEAD tag verification; security event |
| ERR-14 | HP kehilangan kunci setelah reinstall | Warning chat lama mungkin inaccessible | Explicit new identity; backup future P2 |
| ERR-15 | Storage Android penuh saat cache | Upload/download tertunda | Clear cache action, no lost outbox |
| ERR-16 | File > limit | Inline filesize error sebelum upload | File size validation client/server |
| ERR-17 | Upload terputus di 60% | Progress paused/failed, Retry | Resumable or restart, orphan cleanup |
| ERR-18 | Upload sukses, message send gagal | Attachment tidak tampak terkirim | Keep encrypted staged object until final send/retry |
| ERR-19 | Download file sudah dihapus server | Attachment unavailable state | Graceful tombstone / no crash |
| ERR-20 | Metadata MIME tidak sesuai konten | Viewer tidak membuka file berbahaya diam-diam | Type validation, safe file open intents |
| ERR-21 | Kamera/mikrofon denied | Permission explainer & Open Settings | Voice/video fallback jika mungkin |
| ERR-22 | Izin notifikasi denied | In-app warning, chats still function | Contextual reprompt per OS policy |
| ERR-23 | Token FCM expired | Tidak ada janji push, in-app sync OK | Token refresh/revoke invalid tokens |
| ERR-24 | FCM delayed ketika Doze | Pesan muncul ketika sync, notifikasi bisa lambat | High priority only appropriate events; telemetry |
| ERR-25 | App force-stopped | Tidak janjikan incoming push | User guidance; recover at next launch |
| ERR-26 | Full-screen intent ditolak | Heads-up/call notification jika tersedia | OS eligibility/permission detection |
| ERR-27 | Push call terlambat setelah timeout | 'Call already ended' tanpa layar ringing | Validate call ID TTL before show/answer |
| ERR-28 | Duplicate call push | Satu incoming call card | Dedup `call_id` + state machine |
| ERR-29 | Kedua user menelepon bersamaan | Busy/call already active | Atomic call state / conflict rule |
| ERR-30 | NAT gagal direct peer | Calling -> TURN fallback | Managed TURN, tested credentials TTL |
| ERR-31 | TURN unavailable/quota | 'Cannot connect call' | Clear retry, monitor quota; don't hang forever |
| ERR-32 | Switch Wi-Fi ke seluler saat call | Reconnecting label, audio attempts recover | ICE restart + grace timer |
| ERR-33 | Mic Bluetooth dilepas saat call | Audio route switch prompt | Android AudioManager/media track handling |
| ERR-34 | OS kills app during call | Remote sees disconnected/ended | Cleanup server call TTL / foreground policy |
| ERR-35 | Password salah | Generic invalid credentials | Rate limit without account enumeration |
| ERR-36 | Username sudah dipakai saat commit | Inline username taken | Unique DB constraint, suggest edit |
| ERR-37 | Invite digunakan dua orang serentak | Satu berhasil, lain code used | Transaction/atomic token redemption |
| ERR-38 | Signup berhasil tapi profil gagal | Pending setup, not authorized to chat | Compensating action / retry idempotent |
| ERR-39 | Email dimiliki orang lain | Risiko diketahui sebelum pendaftaran | Warn no verified ownership, protect recovery |
| ERR-40 | Brute force username/password | Cooldown/429 generic | IP+account rate-limit, audit abuse |
| ERR-41 | Admin user kehilangan role saat panel terbuka | Aksi selanjutnya ditolak dan panel ditutup | Live role server validation + re-fetch |
| ERR-42 | Admin reset password ketika user aktif | User sign-in refresh/forced auth per policy | Sessions revoke and server status enforcement |
| ERR-43 | Admin menghapus dirinya/admin terakhir | Tombol disabled dan backend reject | Strong invariant transaction |
| ERR-44 | Admin delete user yang punya Storage objects | Dialog pending cleanup, no partial silent deletion | Cleanup/reassign owner then delete, audited job |
| ERR-45 | Akun suspended tetapi JWT belum kedaluwarsa | Akses operasi baru ditolak | DB account status checks + revoked sessions |
| ERR-46 | Block terjadi saat message queued | Bubble Failed 'Not delivered' | Server block check at commit |
| ERR-47 | Read receipts disabled | Sender tak menerima status read | Respect privacy, no fallback inferencing |
| ERR-48 | Pesan dihapus saat lawan offline | Tombstone diterapkan setelah reconnect | Durable E2EE control event |
| ERR-49 | APK update dengan signing key berbeda | Android menolak update | Keep protected keystore; sign pipeline consistency |
| ERR-50 | Build GitHub gagal dependency | CI jelas gagal, tidak publish APK | Lock deps, pin versions, log sanitized |
| ERR-51 | Secret accidentally printed in CI | Stop deployment/security incident | Mask secrets, rotate, review repo/artifacts |
| ERR-52 | RLS policy salah sehingga data user lain bocor | Tidak pernah dianggap acceptable | Automated adversarial tests and release blocker |
| ERR-53 | Perubahan skema lokal saat update | Loading migration dengan backup data | Transactional migrations; rollback plan |
| ERR-54 | Database quota/realtime quota habis | Degraded state, message retry | Alert owner, scale plan or throttle |
| ERR-55 | Theme switch saat chat panjang | Scroll/draft tidak berubah | Stable keyed widgets and persisted state |
| ERR-56 | Font scale 200%/landscape | Semua CTA dapat di-scroll/diakses | Responsive layout + a11y QA |
| ERR-57 | Notification opens a deleted message | Fallback chat/thread | Lookup authoritative latest state |
| ERR-58 | App cache decrypted message leaked to log | Security release blocker | Sanitized logging and crash reporting |
| ERR-59 | Invite/link forwarded to stranger | Registrasi tidak otomatis trusted | One-time TTL, optional intended recipient, admin revoke |
| ERR-60 | Call participant spoofed in signaling | Reject call & security event | Authenticated signaling + key binding |

## 17.1 UX microcopy yang harus konsisten

| Situasi | Copy Indonesia (usulan) | Primary CTA |
|---|---|---|
| Offline saat chat | 'Tidak ada koneksi. Pesan akan dikirim saat online.' | `Coba lagi` pada bubble failed |
| Login gagal | 'Username/email atau password tidak sesuai.' | `Coba lagi` |
| Rate limit | 'Terlalu banyak percobaan. Coba lagi beberapa saat.' | Disabled hingga retry-after |
| Invalid invite | 'Kode undangan tidak dapat digunakan.' | `Gunakan kode lain` |
| Session expired | 'Sesi berakhir. Masuk kembali untuk melanjutkan.' | `Masuk` |
| Unable decrypt | 'Pesan ini belum dapat dibuka dengan aman.' | `Detail keamanan` |
| Key changed | 'Identitas keamanan kontak ini berubah.' | `Verifikasi kontak` |
| Storage full | 'Penyimpanan perangkat hampir penuh.' | `Kelola penyimpanan` |
| Upload failed | 'File belum terkirim.' | `Coba lagi` |
| Call expired | 'Panggilan ini sudah berakhir.' | `Tutup` |
| Mic blocked | 'Adoetz Chat memerlukan akses mikrofon untuk panggilan.' | `Buka pengaturan` |
| Delete user | 'Hapus akun ini? Tindakan ini dapat berdampak pada data dan sesi pengguna.' | `Tinjau penghapusan` |

# 18. Privasi, keamanan operasional, dan abuse prevention

## 18.1 Kontrol akun

- Password policy aman, transport TLS, anti-credential stuffing, password manager/autofill, jangan log password, PII, access token, private keys.
- Login request harus memiliki rate limit dengan respons generik. Gunakan security headers dan validasi schema untuk Edge Functions.
- Profile/avatar uploads divalidasi ukuran, type, content, dan akses; server boleh melihat avatar/profil karena bukan bagian E2EE message unless further encrypted.
- Block dan report: untuk E2EE reports, user **secara sadar memilih** membagikan konten tertentu ke admin, dengan consent eksplisit; jangan backdoor otomatis.
- Akun suspended tidak dapat berkomunikasi, tetapi cleanup dan appeal process dapat diputuskan nanti.

## 18.2 Admin safety

- Tidak ada role selection pada signup; admin pertama dipromosikan secara manual oleh project owner.
- Setiap action penting: live authorization + step-up auth + reason + audit + idempotency.
- Last admin protection, no self-escalation, separation of duty jika skala bertambah.
- Suspended vs soft-deleted vs hard-deleted punya semantik terpisah; soft-delete memberi masa pemulihan **PROPOSED** 7 hari, tetapi retensi wajib disepakati.
- Password force reset tidak berarti private key recovery; tampilkan dampak ke admin dan user.

## 18.3 Supply chain & client build

- Pin dependencies dan commit `pubspec.lock`, review plugin Flutter native, scan Dependabot/GitHub advisories, secret scanning.
- Release signing key wajib privat, di-backup terenkripsi dan akses terbatas; rilis identik ditandatangani konsisten.
- Protect branch `main`, pull request review bila berkolaborasi, GitHub Actions permissions minimal, jangan menjalankan untrusted PR dengan akses release secrets.
- APK downloadable dengan checksum SHA-256 dan tag version; signature verifier bila perlu.

# 19. Arsitektur client dan rekomendasi modul Flutter

**Prinsip:** clean boundaries, bukan overengineering. Feature-first directory, state predictable, encrypted local persistence, dependency injection.

```text
lib/
  app/
    app.dart
    router.dart
    theme/                 # dark, light, tokens, components
    bootstrap/             # startup, session, migration
  core/
    network/               # Supabase client, retry, connectivity
    auth/                  # sessions, permissions
    crypto/                # E2EE interfaces, native bridge
    storage/               # encrypted local database, files
    notifications/         # FCM, local notifications, intent routing
    realtime/              # channel management, resync
    ui/                    # shared widget library and error states
  features/
    onboarding/
    authentication/
    profile/
    people_search/
    chats/
    attachments/
    calls/
    security/
    settings/
    admin/
  l10n/                     # Indonesian first, English ready
  main.dart
```

**Packages:** pilih paket Riverpod/Bloc, routing, local DB, Flutter WebRTC, secure storage, FCM, notification/call integration, permission handler dan image/file pickers berdasarkan compatibility matrix versi Flutter/Android terbaru sebelum memasukkannya ke `pubspec.yaml`. PRD tidak mengunci library E2EE sebelum POC.

## 19.1 State management

- Session state tunggal; role changes observable namun server tetap otoritatif.
- Outbox state machine persisted; optimistic UI harus direkonsiliasi.
- Call state machine centralized; hindari dua widget mengendalikan mic/camera tracks.
- Theme state global reactive; settings per-user dikonfirmasi saat login.
- Navigation guard: session, suspended, crypto-ready, admin-only, ongoing call.

# 20. GitHub Actions dan lifecycle APK

## 20.1 Repository dan environments

```text
adoetz-chat/
  .github/workflows/
    analyze-test.yml
    build-android.yml
    release-android.yml
  android/
  lib/
  test/
  integration_test/
  supabase/
    migrations/
    functions/
    tests/
  docs/
    product/
    architecture/
    security/
  pubspec.yaml
  pubspec.lock
  README.md
```

Environments **staging** dan **production** menggunakan dua Supabase projects atau dua isolated environments (sangat disarankan) serta Firebase configuration masing-masing, walaupun pada tahap awal minimal staging aman harus tersedia. Jangan melakukan eksperimen migrasi langsung di DB produksi.

## 20.2 CI flow

1. Trigger PR/main/manual (`workflow_dispatch`).
2. Checkout, setup JDK/Flutter yang tervalidasi, restore dependency cache.
3. `flutter pub get`, format check, static analyzer, unit/widget tests, dependency/license/security checks.
4. Integration tests bila device runner/emulator tersedia, API contract/RLS tests pada staging.
5. Inject publishable Supabase URL/key dan Firebase app config sesuai environment; secret backend tetap di Supabase secrets, bukan APK.
6. Build APK release di protected branch/tag menggunakan keystore terenkripsi di GitHub Actions secrets, versionCode meningkat.
7. Upload APK sebagai artifact, generate SHA-256, publish GitHub Release pada tag yang disetujui.
8. Smoke install/update test di dua perangkat nyata; rollback ke last signed-good release jika beta fail.

## 20.3 Versioning & distribution

- Version: semantic `MAJOR.MINOR.PATCH`, Android `versionCode` strictly increases.
- First alpha `0.1.0`; rilis `1.0.0` setelah security/call/QA gates selesai.
- `main` branch bukan otomatis berarti layak produksi: alpha artifact boleh otomatis, release tagged manual approval.
- Release notes menjelaskan fitur, known issues, dan apakah update mengubah key/session.
- Uji install bersih, upgrade antarversi, low storage update, package ID benar `com.adoetzchat.messenger`.
- Bila keystore hilang atau signing berubah, pengguna mungkin tidak dapat update APK lama; mitigasi: offsite encrypted backup dan documented recovery process.

# 21. Nonfunctional requirements (NFR)

| ID | Kategori | Persyaratan yang dapat diuji |
|---|---|---|
| NFR-01 | Security | Semua protected endpoints/RLS menolak unauthorized direct API requests |
| NFR-02 | E2EE | Tidak ada plaintext di database/Storage/network server payload/log; pengecualian profil publik yang dijelaskan |
| NFR-03 | Resilience | Offline outbox survive app kill/relaunch, reconnect, timeout dan retry |
| NFR-04 | Performance | Smooth chat list 1.000+ pesan lokal pada reference device; profiling memory & frame drop |
| NFR-05 | Battery | Realtime backoff idle dan presence throttled; background restrictions respected |
| NFR-06 | Resource | Batas cache + clear cache; file uploads bounded; no unbounded in-memory attachment |
| NFR-07 | Accessibility | Screen readers, font scale hingga 200%, touch targets >= 48 dp, contrast AA |
| NFR-08 | Privacy | Analytics/crash logs tanpa message plaintext, secrets, private keys, email yang tidak perlu |
| NFR-09 | Observability | Correlation ID, request failure rate, queue depth, latency, reconnect counts, push delivery estimates |
| NFR-10 | Maintainability | Modular Flutter code, automated tests, migrations, ADR untuk keputusan arsitektur |
| NFR-11 | Compatibility | CI builds correct APK; matrix Android SDK versions/OEMs; supports theme/system settings |
| NFR-12 | Backup | DB backup provider and recovery drills; jangan mengklaim backup server bisa memulihkan E2EE messages |
| NFR-13 | Availability | Graceful degrade saat Supabase/FCM/TURN failure; health indicators yang tidak misleading |
| NFR-14 | Retention | Formal policy tentang logs, orphan uploads, invites, deleted accounts, message retention |

## 21.1 Observability yang tidak melanggar E2EE

Track agregat: successful registration count, login error codes, time-to-message-server-ack, delivery latency (aggregate), reconnect attempts, call connection success/failure buckets, TURN usage, DB/storage size, build failures, app crashes. **Tidak** track teks pesan, file nama plaintext, decrypted attachment, contact graph lengkap di analytics, identity private key, password, exact invite code, atau auth token.

# 22. Rencana pengujian dan acceptance tests

## 22.1 Test pyramid

- **Unit:** input validators, username normalization, outbox retry/idempotency, message state reducer, call state machine, theme tokens.
- **Widget:** setiap layar default/empty/loading/error; login password hidden; accessibility labels; navigation/back; no overflow large font.
- **Integration:** signup invite, login/out, session expiration, admin actions, RLS direct API tests, push token registration, file encrypted roundtrip.
- **End-to-end dua device:** simultaneous DM, offline sender/receiver, read receipts, key change, call voice/video, lock screen, installed APK update.
- **Security:** direct API abuse, RLS cross-user, role escalation, stored XSS-like string rendering, URL/deeplink validation, dependency tamper, insecure local key store, replay/tamper ciphertext, MITM on signaling.
- **Chaos/reliability:** force airplane mode at each send state, kill app mid-encryption, network handover, Supabase 5xx, duplicate realtime events, FCM delay, TURN failure.

## 22.2 Minimum device test matrix

| Parameter | Coverage minimum |
|---|---|
| Android | Android 10, 12, 13, 14, 15+, latest installed device |
| OEM | Pixel/Android dekat AOSP, Samsung, Xiaomi/HyperOS, satu OEM agresif battery management |
| Hardware | Low RAM, average midrange, high-end; storage almost full |
| Network | Wi-Fi, 4G/5G, restricted NAT, slow 2G simulation, offline, VPN, handover |
| Permission | Allowed/denied/ask later notification, mic, camera, biometric |
| UI | Light/dark/system, font 100/150/200%, portrait/landscape, keyboard open |
| App lifecycle | Foreground, background, screen locked, Doze, process death, force-stop |
| Identity | Single device, reinstall, key change, password reset, account suspension |

## 22.3 Explicit acceptance scenarios

**AC-01 Signup role:** Given valid invite and username/email/password, when register succeeds, then exactly one user/profile row exists, role = `user`, email confirmation is not required, and no admin claim is reachable.

**AC-02 Duplicate username:** Given a concurrent collision, exactly one account receives the username and the other receives a friendly conflict without corrupting invitation usage.

**AC-03 Admin blocked:** Given role `user`, direct request to privileged function and direct table mutation both fail; hidden buttons alone are not accepted as security.

**AC-04 Offline send:** Given no network after composition, one queued bubble persists through app kill; after reconnect exactly one server message is created and status advances.

**AC-05 E2EE confidentiality:** Given DB dump and Storage read access but no private keys, testers cannot reconstruct original plaintext text/file; all key change checks behave as documented.

**AC-06 Device loss:** Given reinstall without crypto backup, user sees explicit identity reset warning; neither admin reset password nor server login silently restores old plaintext history.

**AC-07 Push privacy:** Given background push, captured FCM requests do not contain plaintext message, attachment key, or encrypted storage credentials.

**AC-08 Incoming call stale:** Given call already ended, delayed push opens 'Call ended' rather than ringing indefinitely; no leaked microphone track.

**AC-09 Revoked/suspended:** Given target suspended while online, protected request fails under server policy and new Realtime access is disallowed/revoked according to TTL policy.

**AC-10 Signing update:** Given beta APK N installed, install signed APK N+1 with same package ID and signing key succeeds without losing permitted local state.

**AC-11 Theme accessibility:** Given system dark/light toggle and font scale 200%, no unscrollable critical actions; contrast and screen reader checks pass.

**AC-12 Admin reset:** Given admin resets password, audit contains actor/target/action but not password; E2EE history remains unintelligible to admin.

# 23. Roadmap implementasi dan dependency gates

| Milestone | Deliverable | Exit gate |
|---|---|---|
| M0: Product & Security Discovery | PRD final, threat model, data retention, E2EE POC, FCM/call feasibility POC | Tidak ada blocker protokol E2EE; stack compatible |
| M1: Foundation | Flutter shell, UI design system, Auth/invites/RBAC/admin basic, CI build signed APK | P0 auth/RLS/security tests pass |
| M2: Secure Text Chat | contact discovery, 1:1 encrypted text, durable outbox, realtime/catch-up sync, receipts | AC-04/05/06 + chaos tests pass |
| M3: Push & Media | FCM, encrypted file/voice note, upload policy | Captured push safe; file integrity/quotas pass |
| M4: Calling | WebRTC voice/video, TURN, incoming call background, logs | Multi OEM/network test; fallback works |
| M5: Closed Beta | Hardening, analytics, crash reporting, a11y, QA matrix, release governance | Security review complete; performance targets met |
| M6: P2 Roadmap | Groups, multi-device, encrypted backup, more platforms | Separate PRD extensions and threat modeling |

**Critical path:** E2EE design and its persistence/integration must be proved before implementing a large set of chat UI polish. Call signaling + Android background restrictions get a separate spike because they can materially affect schedule.

# 24. Product analytics, privacy notices, dan policy decisions

- Privacy Policy menjelaskan account data, metadata, ciphertext storage, push token, call signaling and retention.
- App Terms/AUP mengatur penggunaan privat dan account suspension, terpisah dari klaim E2EE.
- Undangan punya expiry default dan kuota; rate limit untuk search/invite/login.
- Account deletion: pilih retention windows untuk encrypted messages yang dikirim ke lawan bicara, avatars, orphan Storage, logs, audit trail, backups. Tidak menjanjikan pemusnahan data yang belum diterapkan secara teknis.
- Opt-in optional crash/diagnostic data; sensitive values scrubbed. Admin actions harus tercatat walaupun E2EE content tidak tersedia.
- App Update policy menjelaskan jika rebuild APK dari source tanpa signature yang sama tidak dapat menggantikan instalasi sebelumnya.

# 25. Open decisions / keputusan yang harus ditutup

| Priority | Pertanyaan keputusan | Rekomendasi baseline |
|---|---|---|
| BLOCKER | Siapa yang bisa mendapatkan invite? | Admin membuat undangan one-time, 7 hari expiry |
| BLOCKER | Cara registrasi server-gated tanpa email confirmation? | Validasi invite sebelum create user melalui supported backend Auth gate, dibuktikan dengan direct API test |
| BLOCKER | Library E2EE Flutter/Android dan support lifecycle? | Pilih setelah POC native/FFI dan external review |
| BLOCKER | Recovery saat device hilang? | V1 tanpa chat recovery, tampil warning terang; P2 encrypted backup |
| BLOCKER | Admin reset password, distribusi kredensial? | Force password reset via secure out-of-band procedure, no plain password in logs |
| HIGH | Single device vs multi device? | Single E2EE device v1 |
| HIGH | Chat search server or local? | Local decrypted search only |
| HIGH | Email no-verification risk? | Display clear caveat; disable email-only recovery sampai verified channel tersedia |
| HIGH | Hosting TURN dan budget? | Managed TURN untuk beta, measure relay traffic |
| HIGH | APK alpha signing? | Protected release keystore from first distributable test |
| HIGH | Soft-delete retention duration? | 7 hari provisional, legal/privacy review |
| MEDIUM | Unread/read receipts default? | On by default with opt-out |
| MEDIUM | Discoverability default? | Username searchable for invited users; privacy toggle |
| MEDIUM | Font/localization? | Bahasa Indonesia default, English-ready |
| MEDIUM | Attachment limits? | Proposed beta limits until capacity test |
| MEDIUM | Admin UI within app vs web? | Within Flutter app first; optional web control panel later |

# 26. Definition of Done (DoD) rilis beta

Rilis beta Adoetz Chat baru dianggap siap jika:

1. Seluruh layar P0/P1 yang diumumkan mempunyai happy path, empty, loading, offline, permission, error dan retry behavior.
2. Signup memenuhi invite restriction dan role default user meski endpoint dipanggil tanpa Flutter.
3. Semua direct API access untuk roles/tables/storage/realtime lulus RLS adversarial testing.
4. E2EE implementation dan key lifecycle lulus review; server/FCM/logs tidak mengandung plaintext pesan/file.
5. Message delivery/dedup/sync lulus chaos test proses mati, reconnect, timeout, duplicate events dan clock skew.
6. Voice/video call tidak memblokir aplikasi dan memiliki fallback nyata untuk TURN, permission, delayed FCM dan incoming UI restrictions.
7. Admin tindakan destructive dan reset tercatat audit, tidak bisa privilege escalation atau delete admin terakhir.
8. Tema dark/light/system, font scale, touch target, screen reader dan small display diuji.
9. APK ditandatangani release signing key yang tersimpan aman; update N->N+1 lulus di perangkat nyata.
10. Privacy notice, retention policy, support workflow, monitor quotas, incident rollback, dan release notes tersedia.

---

# 27. Lampiran A - Status prioritas per fitur

| Domain | Fitur | Priority | Validation gate |
|---|---|---|---|
| App shell | Branding, themes, navigasi, responsive | P0 | UI + a11y |
| Auth | Invite-only sign up; username/email/password | P0 | Direct Auth/API adversarial |
| Auth | Logout/session expiry/device lock | P0 | Lifecycle/security |
| Users | Profile, username search, block | P0 | Search/privacy/anti-enumeration |
| Admin | Role user default, user list, suspend, reset, delete, audit | P0 | RBAC + privileged ops |
| Chat | 1:1 encrypted text | P0 | E2EE audit gate |
| Chat | Offline outbox, delivery/read receipts, scroll/pagination | P0 | Chaos/idempotency |
| Push | FCM background wake + minimal payload | P0 | Doze/permission/privacy |
| Media | Photo/video/document ciphertext upload | P1 | Integrity/quota/retry |
| Media | Voice notes | P1 | Mic/format/encryption |
| Chat UX | Reply, reactions, edit/delete E2EE | P1 | Sync/versioning |
| Call | 1:1 voice/video + TURN | P1 | Android/OEM/network |
| Security | App lock/biometric, key verify QR | P1 | Native/device |
| Messaging | Disappearing messages | P2 | Remote deletion limitations |
| Messaging | Group E2EE | P2 | Group key management |
| Account | Multi-device | P2 | Session/key architecture |
| Account | Encrypted backup recovery | P2 | Backup threat model |
| Platform | iOS, Web, Desktop | P2 | Per-platform security gate |

# 28. Lampiran B - Prinsip wireframe per layar

```text
[CHATS - DARK]                         [CHAT DETAIL - DARK]
┌──────────────────────┐              ┌──────────────────────┐
│ Chats           +  ◯ │              │ ‹ Alex        ☎  ▣  │
│ ┌──────────────────┐ │              │──────────────────────│
│ │ Search chats...  │ │              │       Yesterday      │
│ └──────────────────┘ │              │ ┌───────────────┐    │
│ ◯ Alex        09:42  │              │ │ Hey, how are  │    │
│   See you tomorrow ② │              │ │ you doing?    │    │
│ ◯ Adoetz       08:15 │              │ └───────────────┘    │
│   Sent a photo       │              │     ┌─────────────┐  │
│ ◯ Project Team       │              │     │ All good! ✓✓│  │
│   Voice message      │              │     └─────────────┘  │
│                      │              │                      │
│ Chats Calls People ⚙ │              │  + [Message...]  ➤   │
└──────────────────────┘              └──────────────────────┘

[ADMIN USER DETAIL]                    [SETTINGS - APPEARANCE]
┌──────────────────────┐              ┌──────────────────────┐
│ ‹ User Details       │              │ ‹ Appearance         │
│          ◯           │              │ Theme                │
│        @alex         │              │ ◉ Follow system      │
│ Role: user           │              │ ○ Always dark        │
│ Status: active       │              │ ○ Always light       │
│──────────────────────│              │                      │
│ Suspend account      │              │ Preview              │
│ Force password reset │              │ [incoming] [outgoing]│
│ Revoke sessions      │              │                      │
│ Delete account       │              │                      │
└──────────────────────┘              └──────────────────────┘
```

**Catatan wireframe:** diagram hanya struktur informasi. Final spacing, a11y, bubble tails, iconography, transitions, dialog dan keyboard behavior harus memakai design tokens dalam bab 6.

# 29. Lampiran C - Referensi resmi untuk verifikasi implementasi

Referensi ini untuk validasi teknis sebelum coding; perilaku layanan dan versi SDK dapat berubah.

1. Supabase Auth general configuration (Confirm Email): https://supabase.com/docs/guides/auth/general-configuration
2. Supabase User Management / deletion and session caveats: https://supabase.com/docs/guides/auth/managing-user-data
3. Supabase Dart Admin updateUserById: https://supabase.com/docs/reference/dart/auth-admin-updateuserbyid
4. Supabase Dart Admin deleteUser: https://supabase.com/docs/reference/dart/auth-admin-deleteuser
5. Supabase Realtime authorization: https://supabase.com/docs/guides/realtime/authorization
6. Supabase Broadcast / Postgres Changes scalability: https://supabase.com/docs/guides/realtime/subscribing-to-database-changes
7. Supabase RLS security concepts: https://supabase.com/docs/guides/getting-started/the-supabase-way-to-build
8. Firebase FCM Android message priority: https://firebase.google.com/docs/cloud-messaging/android-message-priority
9. Android 14 Full-screen intent behavior: https://developer.android.com/about/versions/14/behavior-changes-14
10. GitHub Actions official docs: https://docs.github.com/en/actions
11. Flutter official documentation: https://docs.flutter.dev/

---

**Akhir PRD v1.0.** Dokumen ini merupakan produk spesifikasi komprehensif; belum merupakan kode Flutter, migration SQL, pengujian security, atau bukti bahwa produk telah diimplementasikan. Semua **BLOCKER** harus diselesaikan sebelum release keamanan produksi.
