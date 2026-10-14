const isDemo = !window.SIANTRI || !window.SIANTRI.url || window.SIANTRI.url.includes('GANTI-DENGAN');
window.isDemo = isDemo;

const $ = s => document.querySelector(s);
const $$ = s => document.querySelectorAll(s);
const today = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Jakarta' });
const LABEL = { waiting: 'Menunggu', called: 'Dipanggil', done: 'Selesai', skipped: 'Dilewati', cancelled: 'Dibatalkan' };
const SVC_ICON = { 'A': '🏦', 'B': '💰', 'C': 'ℹ️', 'D': '📋', 'E': '🔑', 'F': '📦' };

/* ── Theme ── */
function getTheme() { return localStorage.getItem('siantri_theme') || 'dark'; }
function setTheme(t) {
  localStorage.setItem('siantri_theme', t);
  document.documentElement.setAttribute('data-theme', t);
}
setTheme(getTheme());
function toggleTheme() {
  const next = getTheme() === 'dark' ? 'light' : 'dark';
  setTheme(next);
  const btn = $('#themeBtn');
  if (btn) btn.textContent = next === 'dark' ? '☀️' : '🌙';
}

/* ── Customer Account (Demo) ── */
function getDemoCustomers() {
  const raw = localStorage.getItem('siantri_demo_customers');
  if (raw) return JSON.parse(raw);
  const def = [
    { id: 'cust-demo1', name: 'Pelanggan Demo', email: 'pelanggan@siantri.com', phone: '08123456789', password: 'pelanggan123', created_at: new Date().toISOString() }
  ];
  localStorage.setItem('siantri_demo_customers', JSON.stringify(def));
  return def;
}
function saveDemoCustomers(list) {
  localStorage.setItem('siantri_demo_customers', JSON.stringify(list));
}
function getCustomerSession() {
  const raw = localStorage.getItem('siantri_customer_session');
  return raw ? JSON.parse(raw) : null;
}
function setCustomerSession(cust) {
  if (cust) localStorage.setItem('siantri_customer_session', JSON.stringify(cust));
  else localStorage.removeItem('siantri_customer_session');
}
function customerRegister(name, email, phone, password) {
  if (!name || !email || !password) return { error: 'Nama, email, dan kata sandi wajib diisi' };
  const customers = getDemoCustomers();
  if (customers.find(c => c.email === email)) return { error: 'Email sudah terdaftar' };
  const cust = { id: 'cust-' + Date.now() + '-' + Math.random().toString(36).slice(2, 6), name, email, phone: phone || '', password, created_at: new Date().toISOString() };
  customers.push(cust);
  saveDemoCustomers(customers);
  const session = { id: cust.id, name: cust.name, email: cust.email, phone: cust.phone };
  setCustomerSession(session);
  return { data: session, error: null };
}
function customerLogin(email, password) {
  const customers = getDemoCustomers();
  const cust = customers.find(c => c.email === email && c.password === password);
  if (!cust) return { error: 'Email atau kata sandi salah' };
  const session = { id: cust.id, name: cust.name, email: cust.email, phone: cust.phone };
  setCustomerSession(session);
  return { data: session, error: null };
}
function customerLogout() {
  setCustomerSession(null);
  localStorage.removeItem('siantri_ticket');
}

/* ── Rating System ── */
function getDemoRatings() {
  const raw = localStorage.getItem('siantri_demo_ratings');
  return raw ? JSON.parse(raw) : [];
}
function saveDemoRating(ticketId, rating, comment) {
  const list = getDemoRatings();
  list.push({ ticket_id: ticketId, rating, comment: comment || '', created_at: new Date().toISOString(), customer_id: (getCustomerSession()||{}).id });
  localStorage.setItem('siantri_demo_ratings', JSON.stringify(list));
}
function getRatingForTicket(ticketId) {
  return getDemoRatings().find(r => r.ticket_id === ticketId);
}
function getAvgRating() {
  const ratings = getDemoRatings();
  if (!ratings.length) return 0;
  return (ratings.reduce((s, r) => s + r.rating, 0) / ratings.length).toFixed(1);
}

/* ── Confetti ── */
function launchConfetti() {
  const canvas = document.createElement('canvas');
  canvas.id = 'confetti-canvas';
  canvas.style.cssText = 'position:fixed;inset:0;z-index:999;pointer-events:none;width:100%;height:100%';
  document.body.appendChild(canvas);
  const ctx = canvas.getContext('2d');
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  const pieces = [];
  const colors = ['#7c83ff', '#2dd4ee', '#34d399', '#fbbf24', '#f87171', '#a78bfa', '#fb923c'];
  for (let i = 0; i < 120; i++) {
    pieces.push({
      x: Math.random() * canvas.width,
      y: Math.random() * canvas.height - canvas.height,
      w: Math.random() * 10 + 5,
      h: Math.random() * 6 + 3,
      color: colors[Math.floor(Math.random() * colors.length)],
      vy: Math.random() * 3 + 2,
      vx: (Math.random() - 0.5) * 4,
      rot: Math.random() * 360,
      vr: (Math.random() - 0.5) * 10,
      opacity: 1
    });
  }
  let frame = 0;
  function tick() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    frame++;
    pieces.forEach(p => {
      p.x += p.vx;
      p.y += p.vy;
      p.rot += p.vr;
      p.vy += 0.04;
      if (frame > 80) p.opacity = Math.max(0, p.opacity - 0.015);
      ctx.save();
      ctx.translate(p.x, p.y);
      ctx.rotate(p.rot * Math.PI / 180);
      ctx.globalAlpha = p.opacity;
      ctx.fillStyle = p.color;
      ctx.fillRect(-p.w / 2, -p.h / 2, p.w, p.h);
      ctx.restore();
    });
    if (frame < 180) requestAnimationFrame(tick);
    else canvas.remove();
  }
  tick();
}

/* ── Browser Notifications ── */
function requestNotification() {
  if (!('Notification' in window)) return;
  if (Notification.permission === 'default') Notification.requestPermission();
}
function notifyBrowser(title, body) {
  if (!('Notification' in window) || Notification.permission !== 'granted') return;
  try { new Notification(title, { body, icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><text y=".9em" font-size="90">🎫</text></svg>' }); } catch(e) {}
}

/* ── Elapsed Timer ── */
function formatElapsed(isoStr) {
  if (!isoStr) return '';
  const diff = Math.floor((Date.now() - new Date(isoStr).getTime()) / 1000);
  if (diff < 60) return `${diff} detik`;
  if (diff < 3600) return `${Math.floor(diff / 60)} menit`;
  return `${Math.floor(diff / 3600)} jam ${Math.floor((diff % 3600) / 60)} menit`;
}

/* ── Demo Data ── */
function getDemoServices() {
  const s = localStorage.getItem('siantri_demo_services');
  if (s) return JSON.parse(s);
  const def = [
    { id: 1, code: 'A', name: 'Customer Service', avg_minutes: 6 },
    { id: 2, code: 'B', name: 'Teller', avg_minutes: 3 },
    { id: 3, code: 'C', name: 'Informasi', avg_minutes: 2 }
  ];
  localStorage.setItem('siantri_demo_services', JSON.stringify(def));
  return def;
}

function getDemoCounters() {
  return [
    { id: 1, name: 'Loket 1', active: true },
    { id: 2, name: 'Loket 2', active: true },
    { id: 3, name: 'Loket 3', active: true }
  ];
}

function getDemoTickets() {
  const raw = localStorage.getItem('siantri_demo_tickets');
  if (raw) return JSON.parse(raw);
  const now = new Date();
  const def = [
    { id: 'demo-t1', service_id: 1, number: 'A001', seq: 1, status: 'waiting', counter_id: null, queue_date: today(), created_at: new Date(now.getTime() - 1000 * 60 * 15).toISOString(), called_at: null, done_at: null },
    { id: 'demo-t2', service_id: 2, number: 'B001', seq: 1, status: 'waiting', counter_id: null, queue_date: today(), created_at: new Date(now.getTime() - 1000 * 60 * 8).toISOString(), called_at: null, done_at: null }
  ];
  localStorage.setItem('siantri_demo_tickets', JSON.stringify(def));
  return def;
}

function saveDemoTickets(list) {
  localStorage.setItem('siantri_demo_tickets', JSON.stringify(list));
  localStorage.setItem('siantri_demo_sync_ts', String(Date.now()));
  window.dispatchEvent(new CustomEvent('siantri_demo_sync'));
}

function makeChain(getData) {
  const p = Promise.resolve().then(() => ({ data: getData(), error: null }));
  p.select = () => makeChain(getData);
  p.order = () => makeChain(getData);
  p.eq = (field, val) => makeChain(() => getData().filter(x => x[field] === val));
  p.neq = (field, val) => makeChain(() => getData().filter(x => x[field] !== val));
  return p;
}

const mockSb = {
  auth: {
    async signInAnonymously() { return { data: {}, error: null }; },
    async getSession() {
      const s = localStorage.getItem('siantri_demo_session');
      return { data: { session: s ? JSON.parse(s) : null }, error: null };
    },
    async signInWithPassword({ email, password }) {
      if (email === 'petugas@siantri.com' && password === 'petugas123') {
        const session = { user: { id: 'petugas-demo', email: 'petugas@siantri.com' } };
        localStorage.setItem('siantri_demo_session', JSON.stringify(session));
        return { data: { session, user: session.user }, error: null };
      }
      if (email === 'admin@siantri.com' && password === 'admin123') {
        const session = { user: { id: 'admin-demo', email: 'admin@siantri.com' } };
        localStorage.setItem('siantri_demo_session', JSON.stringify(session));
        return { data: { session, user: session.user }, error: null };
      }
      return { data: { session: null, user: null }, error: { message: 'Email atau kata sandi salah' } };
    },
    async signOut() {
      localStorage.removeItem('siantri_demo_session');
      return { error: null };
    }
  },
  from(tbl) {
    if (tbl === 'services') {
      return { select: () => makeChain(getDemoServices) };
    }
    if (tbl === 'counters') {
      return { select: () => makeChain(getDemoCounters) };
    }
    if (tbl === 'tickets' || tbl === 'display_board') {
      return {
        select: () => makeChain(getDemoTickets),
        update: (patch) => ({
          eq: (field, val) => {
            const list = getDemoTickets();
            const item = list.find(x => x[field] === val);
            if (item) Object.assign(item, patch);
            saveDemoTickets(list);
            return Promise.resolve({ error: null });
          }
        })
      };
    }
    if (tbl === 'alerts') {
      const getDemoAlerts = () => {
        const raw = localStorage.getItem('siantri_demo_alerts');
        if (raw) return JSON.parse(raw);
        const def = [
          { id: 'al-1', branch_id: 'b1', severity: 'warning', message: 'Trafik antrean Customer Service meningkat +35%', status: 'open', created_at: new Date().toISOString() },
          { id: 'al-2', branch_id: 'b1', severity: 'critical', message: 'Waktu tunggu rata-rata mendekati ambang batas SLA 15 menit', status: 'open', created_at: new Date().toISOString() }
        ];
        localStorage.setItem('siantri_demo_alerts', JSON.stringify(def));
        return def;
      };
      return {
        select: () => makeChain(getDemoAlerts),
        update: (patch) => ({
          eq: (field, val) => {
            const list = getDemoAlerts();
            const item = list.find(x => x[field] === val);
            if (item) Object.assign(item, patch);
            localStorage.setItem('siantri_demo_alerts', JSON.stringify(list));
            return Promise.resolve({ error: null });
          }
        })
      };
    }
    return { select: () => makeChain(() => []) };
  },
  async rpc(fn, args = {}) {
    if (fn === 'branch_metrics') {
      const list = getDemoTickets();
      const waiting = list.filter(t => t.status === 'waiting' && t.queue_date === today()).length;
      const serving = list.filter(t => t.status === 'called' && t.queue_date === today()).length;
      const served = list.filter(t => t.status === 'done' && t.queue_date === today()).length;
      const skipped = list.filter(t => t.status === 'skipped' && t.queue_date === today()).length;
      const total = waiting + serving + served + skipped;
      const no_show_pct = total > 0 ? Math.round((skipped / total) * 100) : 0;
      return {
        data: {
          waiting,
          serving,
          served,
          avg_wait_min: 5,
          no_show_pct,
          active_counters: 3
        },
        error: null
      };
    }
    if (fn === 'forecast') {
      const now = new Date();
      const rows = [];
      for (let i = 1; i <= 8; i++) {
        const d = new Date(now.getTime() + i * 3600 * 1000);
        const exp = Math.max(3, Math.floor(7 + Math.sin(i) * 5));
        rows.push({
          hour_ts: d.toISOString(),
          expected: exp,
          counters_needed: Math.max(1, Math.ceil(exp / 4))
        });
      }
      return { data: rows, error: null };
    }
    if (fn === 'branch_compare') {
      const csat = Number(getAvgRating()) || 4.8;
      return {
        data: [
          { name: 'Cabang Utama (Demo)', avg_wait: 4.2, p90_wait: 7.8, sla_pct: 96, csat: csat },
          { name: 'Cabang Barat', avg_wait: 5.6, p90_wait: 9.1, sla_pct: 92, csat: 4.6 },
          { name: 'Cabang Timur', avg_wait: 6.1, p90_wait: 10.4, sla_pct: 88, csat: 4.4 }
        ],
        error: null
      };
    }
    if (fn === 'issue_ticket') {
      const services = getDemoServices();
      const s = services.find(x => x.id === args.p_service);
      if (!s) return { data: null, error: { message: 'Layanan tidak ditemukan' } };
      const list = getDemoTickets();
      const todayList = list.filter(t => t.service_id === s.id && t.queue_date === today());
      const seq = todayList.length + 1;
      const num = s.code + String(seq).padStart(3, '0');
      const custSession = getCustomerSession();
      const ticket = {
        id: 'ticket-' + Date.now() + '-' + Math.random().toString(36).slice(2, 6),
        service_id: s.id,
        number: num,
        seq: seq,
        status: 'waiting',
        counter_id: null,
        queue_date: today(),
        customer_id: custSession ? custSession.id : null,
        phone: args.p_phone || (custSession ? custSession.phone : null) || null,
        created_at: new Date().toISOString(),
        called_at: null,
        done_at: null
      };
      list.push(ticket);
      saveDemoTickets(list);
      return { data: ticket, error: null };
    }
    if (fn === 'cancel_ticket') {
      const list = getDemoTickets();
      const t = list.find(x => x.id === args.p_ticket);
      if (t && t.status === 'waiting') {
        t.status = 'cancelled';
        saveDemoTickets(list);
      }
      return { data: null, error: null };
    }
    if (fn === 'call_next') {
      const session = localStorage.getItem('siantri_demo_session');
      if (!session) return { data: null, error: { message: 'Harus login' } };
      const list = getDemoTickets();
      list.forEach(x => {
        if (String(x.counter_id) === String(args.p_counter) && x.status === 'called') {
          x.status = 'done';
          x.done_at = new Date().toISOString();
        }
      });
      const next = list
        .filter(x => x.status === 'waiting' && x.queue_date === today())
        .sort((a, b) => a.created_at.localeCompare(b.created_at))[0];
      if (next) {
        next.status = 'called';
        next.counter_id = args.p_counter;
        next.called_at = new Date().toISOString();
      }
      saveDemoTickets(list);
      return { data: next || null, error: null };
    }
    if (['set_counter', 'start_service', 'heartbeat'].includes(fn)) return { data: null, error: null };
    const list = getDemoTickets(), t = list.find(x => x.id === args.p_ticket);
    if (t && fn === 'recall_ticket') t.called_at = new Date().toISOString();
    if (t && fn === 'complete_ticket') { t.status = 'done'; t.done_at = new Date().toISOString(); }
    if (t && fn === 'no_show') { t.status = 'skipped'; t.done_at = new Date().toISOString(); }
    saveDemoTickets(list);
    return { data: null, error: null };
  },
  channel() {
    return {
      on(evt, opt, fn) {
        window.addEventListener('storage', (e) => {
          if (e.key === 'siantri_demo_sync_ts') fn();
        });
        window.addEventListener('siantri_demo_sync', fn);
        return { subscribe: () => ({}) };
      },
      subscribe: () => ({})
    };
  }
};

const sb = isDemo ? mockSb : supabase.createClient(window.SIANTRI.url, window.SIANTRI.key);

let BRANCH = null;
async function ensureUser() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) await sb.auth.signInAnonymously();
}
async function load() {
  if (!BRANCH && !isDemo) {
    const b = await sb.from('branches').select('id').order('name');
    BRANCH = window.SIANTRI.branch || (b.data && b.data[0] && b.data[0].id);
  }
  const f = q => (BRANCH ? q.eq('branch_id', BRANCH) : q);
  const [s, c, t] = await Promise.all([
    f(sb.from('services').select('*').order('code')),
    f(sb.from('counters').select('*').order('name')),
    f(sb.from('display_board').select('*').order('issued_at'))
  ]);
  const err = s.error || c.error || t.error;
  if (err) toast('Gagal memuat data: ' + err.message);
  const services = (s.data || []).map(x => ({ ...x, avg_minutes: x.avg_minutes || Math.max(1, Math.round((x.avg_service_sec || 300) / 60)) }));
  const tickets = (t.data || []).map(x => ({ ...x, raw: x.status, status: x.status === 'serving' ? 'called' : x.status, created_at: x.created_at || x.issued_at }));
  return { services, counters: c.data || [], tickets };
}

function live(fn) {
  fn();
  sb.channel('q' + Math.random()).on('postgres_changes', { event: '*', schema: 'public', table: 'tickets' }, fn).subscribe();
  setInterval(fn, 10000);
}

function toast(m, type) {
  let el = $('.toast');
  if (!el) { el = document.createElement('div'); el.className = 'toast'; document.body.appendChild(el); }
  el.textContent = m;
  el.className = 'toast show' + (type ? ' toast-' + type : '');
  clearTimeout(el._t);
  el._t = setTimeout(() => el.classList.remove('show'), 3000);
}

const waitingOf = (d, sid) => d.tickets.filter(t => t.service_id === sid && t.status === 'waiting');

function nav(page) {
  const cust = getCustomerSession();
  const themeIcon = getTheme() === 'dark' ? '☀️' : '🌙';
  const custHtml = cust
    ? `<a href="profil.html" class="nav-user">👤 ${cust.name}</a><a href="#" onclick="customerLogout();location.reload();return false" class="nav-logout">Keluar</a>`
    : (page === 'index' || page === 'login' ? '' : '');
  const loginBtn = !cust ? `<a href="login.html" class="btn-nav-login">Masuk / Daftar</a>` : '';
  return `<nav>
    <b>SIAntri</b>
    <a href="index.html" class="${page==='index'?'on':''}">Ambil Nomor</a>
    <a href="monitor.html" class="${page==='monitor'?'on':''}">Monitor</a>
    <a href="admin.html" class="${page==='admin'?'on':''}">Petugas</a>
    <a href="dashboard.html" class="${page==='dashboard'?'on':''}">Dashboard</a>
    <span class="nav-spacer"></span>
    <button id="themeBtn" class="theme-toggle" onclick="toggleTheme()" title="Ganti tema">${themeIcon}</button>
    ${custHtml}${loginBtn}
  </nav>`;
}

/* ── Rating Modal Helper ── */
function showRatingModal(ticketId, ticketNumber, onDone) {
  if (getRatingForTicket(ticketId)) return;
  let selected = 0;
  const overlay = document.createElement('div');
  overlay.className = 'modal-overlay';
  overlay.innerHTML = `
    <div class="modal-card rating-modal">
      <div class="rating-emoji" id="ratingEmoji">😊</div>
      <h2>Bagaimana pengalaman Anda?</h2>
      <p class="mu">Tiket <b>${ticketNumber}</b> telah selesai dilayani</p>
      <div class="stars" id="stars">
        ${[1,2,3,4,5].map(i => `<span class="star" data-v="${i}" onclick="window._rSelect(${i})">★</span>`).join('')}
      </div>
      <p class="mu" id="ratingLabel">Ketuk bintang untuk menilai</p>
      <textarea id="ratingComment" placeholder="Tulis komentar (opsional)..." rows="2"></textarea>
      <div class="row" style="gap:10px;margin-top:14px;justify-content:center">
        <button class="btn" id="ratingSubmit" disabled onclick="window._rSubmit()">Kirim Rating</button>
        <button class="btn ghost" onclick="window._rClose()">Lewati</button>
      </div>
    </div>`;
  document.body.appendChild(overlay);
  setTimeout(() => overlay.classList.add('show'), 10);

  const labels = ['', 'Sangat Buruk 😞', 'Buruk 😕', 'Cukup 😐', 'Baik 😊', 'Luar Biasa 🤩'];
  const emojis = ['😊', '😞', '😕', '😐', '😊', '🤩'];

  window._rSelect = (v) => {
    selected = v;
    overlay.querySelectorAll('.star').forEach(s => {
      s.classList.toggle('active', parseInt(s.dataset.v) <= v);
    });
    overlay.querySelector('#ratingLabel').textContent = labels[v];
    overlay.querySelector('#ratingEmoji').textContent = emojis[v];
    overlay.querySelector('#ratingSubmit').disabled = false;
  };
  window._rSubmit = () => {
    saveDemoRating(ticketId, selected, overlay.querySelector('#ratingComment').value);
    toast('Terima kasih atas feedback Anda! ⭐', 'ok');
    overlay.classList.remove('show');
    setTimeout(() => overlay.remove(), 300);
    if (onDone) onDone();
  };
  window._rClose = () => {
    overlay.classList.remove('show');
    setTimeout(() => overlay.remove(), 300);
    if (onDone) onDone();
  };
}

const _dev = typeof location !== 'undefined' ? new URLSearchParams(location.search).get('device') : null;
if (_dev && !isDemo) setInterval(() => sb.rpc('heartbeat', { p_device: _dev }), 30000);
