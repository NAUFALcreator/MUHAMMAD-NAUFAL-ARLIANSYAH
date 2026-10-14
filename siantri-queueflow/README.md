# SIAntri × QueueFlow (Web + Flutter + Supabase)

Satu backend, dua klien. Web SIAntri (ringan, tanpa build) dan app Flutter (agent, supervisor, manager, admin, kiosk, layar antrean) memakai database yang sama.

```
database/supabase.sql   skema multi-cabang, RLS, RPC, alert, forecast, akun demo
web/                    index, monitor, kiosk, admin (petugas), dashboard
flutter/                main.dart + pubspec.yaml (satu file)
supabase/functions/dispatch   notifikasi WA/SMS/email + webhook bertanda tangan
```

## Setup
1. Supabase > SQL Editor: jalankan `database/supabase.sql`. Aktifkan Auth > Anonymous sign-ins (dan MFA TOTP untuk admin).
2. Akun demo: `petugas@siantri.com` / `petugas123` (agent), `admin@siantri.com` / `admin123` (admin). **Ganti sebelum produksi.**
3. Isi URL + anon key di `web/config.js`, lalu jalankan `jalankan-web.bat` (atau `python -m http.server 8080` dari folder `web/`). Tanpa konfigurasi, web berjalan di mode demo lokal.
4. Flutter: `flutter create app && cd app && flutter pub add supabase_flutter flutter_tts`, salin `flutter/main.dart` ke `app/lib/main.dart`, lalu `flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.
5. Notifikasi/webhook/alert otomatis: aktifkan extension `pg_cron` dan `pg_net`, buka komentar jadwal di akhir bagian "TAMBAHAN" pada SQL, lalu `supabase functions deploy dispatch` dan isi secrets (WA_PHONE_ID, WA_TOKEN, TWILIO_SID, TWILIO_TOKEN, TWILIO_FROM, RESEND_KEY, MAIL_FROM).
6. Layar/kiosk dengan monitoring perangkat: daftarkan di tab Device (Flutter admin), lalu buka web dengan `?device=<id>` atau jalankan Flutter dengan `--dart-define=DEVICE_ID=<id>`.

## Catatan
- Nomor tiket bersifat publik (agar monitor realtime berjalan tanpa login). Nomor HP disimpan di tabel `ticket_contacts` yang terkunci RLS.
- Belum ada: mode offline-first dengan branch gateway, cetak ESC/POS, SSO, dan WhatsApp dua arah.
