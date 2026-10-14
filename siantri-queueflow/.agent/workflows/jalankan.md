---
description: Jalankan versi web SIAntri di localhost:8080
---

1. Pastikan `web/config.js` sudah berisi URL dan anon key Supabase (bukan placeholder GANTI-DENGAN-...).

// turbo
2. Jalankan server statis dari folder web:
`cd web && python -m http.server 8080`

3. Buka `http://localhost:8080`, lalu cek `index.html`, `monitor.html`, dan `admin.html` tanpa error di console.
