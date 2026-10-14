# Aturan Proyek SIAntri × QueueFlow

- Struktur: `web/` (HTML + JS vanilla + Supabase CDN), `flutter/main.dart` (satu file), `database/supabase.sql`, `supabase/functions/`.
- Backend tunggal: skema QueueFlow (uuid, multi-cabang). Web dan Flutter memakai database yang sama; perubahan skema/RPC hanya di `database/supabase.sql`.
- Jaga kode sederhana dan langsung bisa dijalankan. Flutter hanya memakai `supabase_flutter` dan `flutter_tts`.
- Semua teks UI dan komentar dalam Bahasa Indonesia.
- Kredensial hanya anon key (di `web/config.js` dan `--dart-define`); jangan pernah service_role di klien. Service role hanya sebagai secret Edge Function.
- Web dijalankan lewat server lokal port 8080 dari folder `web/`, bukan buka file langsung.
