+import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _url = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://GANTI-DENGAN-PROJECT-ID.supabase.co');
const _key = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: 'YOUR-ANON-KEY');
SupabaseClient get sb => Supabase.instance.client;

final lang = ValueNotifier<String>('id');
const _tr = {
  'id': {'branch': 'Cabang', 'priority': 'Prioritas', 'remote': 'Tiket remote', 'none': 'Belum ada tiket', 'cancel': 'Batalkan', 'out': 'Keluar',
    'next': 'Panggil berikutnya', 'recall': 'Panggil ulang', 'start': 'Mulai', 'done': 'Selesai', 'noshow': 'Tidak hadir', 'transfer': 'Pindahkan',
    'waiting': 'Menunggu', 'serving': 'Dilayani', 'paused': 'Antrian dijeda (mode darurat)', 'soon': 'Giliran kamu hampir tiba!', 'now': 'Kamu dipanggil! Menuju'},
  'en': {'branch': 'Branch', 'priority': 'Priority', 'remote': 'Remote ticket', 'none': 'No ticket yet', 'cancel': 'Cancel', 'out': 'Sign out',
    'next': 'Call next', 'recall': 'Recall', 'start': 'Start', 'done': 'Complete', 'noshow': 'No-show', 'transfer': 'Transfer',
    'waiting': 'Waiting', 'serving': 'Serving', 'paused': 'Queue paused (emergency mode)', 'soon': 'Your turn is almost here!', 'now': 'You are called! Go to'},
};
String t(String k) => _tr[lang.value]![k] ?? k;

const _device = String.fromEnvironment('DEVICE_ID');
Timer? beat() => _device.isEmpty ? null : Timer.periodic(const Duration(seconds: 30), (_) async { try { await sb.rpc('heartbeat', params: {'p_device': _device}); } catch (_) {} });

typedef Rows = List<Map<String, dynamic>>;

Stream<T> poll<T>(Future<T> Function() f, [int sec = 5]) async* {
  while (true) {
    try { yield await f(); } catch (_) {}
    await Future.delayed(Duration(seconds: sec));
  }
}

void toast(BuildContext c, String m) {
  if (c.mounted) ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}

Future<dynamic> run(BuildContext c, Future<dynamic> f) async {
  try { return await f; }
  on PostgrestException catch (e) { toast(c, e.message); }
  on AuthException catch (e) { toast(c, e.message); }
  catch (e) { toast(c, '$e'); }
  return null;
}

Future<List<String>?> ask(BuildContext c, String title, List<String> labels) {
  final ctl = [for (final _ in labels) TextEditingController()];
  return showDialog<List<String>>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < labels.length; i++) TextField(controller: ctl[i], decoration: InputDecoration(labelText: labels[i])),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Batal')),
        FilledButton(onPressed: () => Navigator.pop(d, [for (final x in ctl) x.text.trim()]), child: const Text('OK')),
      ],
    ),
  );
}

Future<Map<String, dynamic>?> pick(BuildContext c, String title, Rows items) => showDialog<Map<String, dynamic>>(
      context: c,
      builder: (d) => SimpleDialog(title: Text(title), children: [
        for (final i in items) SimpleDialogOption(onPressed: () => Navigator.pop(d, i), child: Text('${i['name']}')),
      ]),
    );

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: _url, anonKey: _key);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext c) => ValueListenableBuilder<String>(
        valueListenable: lang,
        builder: (_, __, ___) => MaterialApp(
          title: 'SIAntri',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(colorSchemeSeed: const Color(0xFF7C83FF), brightness: Brightness.dark, useMaterial3: true),
          home: const Gate(),
        ),
      );
}

class TabsPage extends StatelessWidget {
  final String title;
  final Map<String, Widget> tabs;
  const TabsPage({super.key, required this.title, required this.tabs});
  @override
  Widget build(BuildContext c) => DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: [
              TextButton(onPressed: () => lang.value = lang.value == 'id' ? 'en' : 'id', child: Text(lang.value.toUpperCase())),
              IconButton(tooltip: t('out'), icon: const Icon(Icons.logout), onPressed: () => sb.auth.signOut()),
            ],
            bottom: tabs.length > 1 ? TabBar(isScrollable: true, tabs: [for (final k in tabs.keys) Tab(text: k)]) : null,
          ),
          body: TabBarView(children: tabs.values.toList()),
        ),
      );
}

class BranchScope extends StatefulWidget {
  final String? fixed;
  final Widget Function(String id) builder;
  const BranchScope({super.key, this.fixed, required this.builder});
  @override
  State<BranchScope> createState() => _BranchScopeState();
}

class _BranchScopeState extends State<BranchScope> {
  Rows branches = [];
  String? sel;
  @override
  void initState() {
    super.initState();
    sel = widget.fixed;
    if (sel == null) {
      sb.from('branches').select().order('name').then((r) => setState(() {
            branches = List<Map<String, dynamic>>.from(r);
            if (branches.isNotEmpty) sel = branches.first['id'];
          }));
    }
  }

  @override
  Widget build(BuildContext c) {
    if (sel == null) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      if (widget.fixed == null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: DropdownButtonFormField<String>(
            value: sel,
            decoration: InputDecoration(labelText: t('branch')),
            items: [for (final b in branches) DropdownMenuItem(value: b['id'] as String, child: Text('${b['name']}'))],
            onChanged: (v) => setState(() => sel = v),
          ),
        ),
      Expanded(child: KeyedSubtree(key: ValueKey(sel), child: widget.builder(sel!))),
    ]);
  }
}

// ---------------- Gate & Login ----------------
class Gate extends StatelessWidget {
  const Gate({super.key});
  @override
  Widget build(BuildContext c) => StreamBuilder<AuthState>(
        stream: sb.auth.onAuthStateChange,
        builder: (c, _) {
          final u = sb.auth.currentUser;
          if (u == null) return const LoginPage();
          return FutureBuilder<Map<String, dynamic>>(
            key: ValueKey(u.id),
            future: sb.from('profiles').select().eq('id', u.id).single(),
            builder: (c, s) {
              if (s.hasError) return Scaffold(body: Center(child: Text('${s.error}')));
              if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
              final p = s.data!;
              final b = p['branch_id'] as String?;
              final role = p['role'];
              if ((role == 'agent' || role == 'supervisor') && b == null) {
                return TabsPage(title: 'SIAntri', tabs: {'Info': const Center(child: Text('Akun belum ditetapkan ke cabang. Hubungi admin.'))});
              }
              switch (role) {
                case 'agent':
                  return TabsPage(title: 'Agent Console', tabs: {'Counter': AgentPage(branch: b!)});
                case 'supervisor':
                  return TabsPage(title: 'Supervisor', tabs: {
                    'Live': BranchScope(fixed: b, builder: (id) => LivePage(branch: id)),
                    'Alert': BranchScope(fixed: b, builder: (id) => AlertsPage(branch: id)),
                  });
                case 'manager':
                  return TabsPage(title: 'Regional', tabs: {
                    'Regional': const RegionalPage(),
                    'Forecast': BranchScope(builder: (id) => ForecastPage(branch: id)),
                    'Live': BranchScope(builder: (id) => LivePage(branch: id)),
                    'Alert': BranchScope(builder: (id) => AlertsPage(branch: id)),
                  });
                case 'admin':
                  return TabsPage(title: 'Admin', tabs: {
                    'Regional': const RegionalPage(),
                    'Forecast': BranchScope(builder: (id) => ForecastPage(branch: id)),
                    'Live': BranchScope(builder: (id) => LivePage(branch: id)),
                    'Alert': BranchScope(builder: (id) => AlertsPage(branch: id)),
                    'Layanan': BranchScope(builder: (id) => ServicesAdmin(branch: id)),
                    'Rules': BranchScope(builder: (id) => RulesAdmin(branch: id)),
                    'User': const UsersAdmin(),
                    'Device': BranchScope(builder: (id) => DevicesAdmin(branch: id)),
                    'Webhook': const WebhooksAdmin(),
                    'MFA': const MfaPage(),
                    'Audit': const AuditPage(),
                  });
                default:
                  return TabsPage(title: 'SIAntri', tabs: {'Ambil Tiket': const TakePage(), 'Tiket Saya': const MyTicket()});
              }
            },
          );
        },
      );
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final email = TextEditingController(), pass = TextEditingController();
  @override
  Widget build(BuildContext c) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
              Text('SIAntri', style: Theme.of(c).textTheme.displaySmall, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email')),
              TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => run(c, sb.auth.signInWithPassword(email: email.text.trim(), password: pass.text)), child: const Text('Masuk')),
              OutlinedButton(
                onPressed: () async {
                  final r = await run(c, sb.auth.signUp(email: email.text.trim(), password: pass.text));
                  if (r != null) toast(c, 'Akun dibuat. Cek email bila konfirmasi aktif.');
                },
                child: const Text('Daftar'),
              ),
              const Divider(height: 32),
              TextButton(onPressed: () => run(c, sb.auth.signInAnonymously()), child: const Text('Lanjut sebagai pelanggan (tanpa akun)')),
              TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const DisplayPage())), child: const Text('Mode layar antrian')),
              TextButton(onPressed: () => Navigator.push(c, MaterialPageRoute(builder: (_) => const KioskPage())), child: const Text('Mode kiosk')),
            ]),
          ),
        ),
      );
}

// ---------------- Customer ----------------
class TakePage extends StatefulWidget {
  const TakePage({super.key});
  @override
  State<TakePage> createState() => _TakeState();
}

class _TakeState extends State<TakePage> {
  String? branch;
  bool prio = false, remote = false;
  final phone = TextEditingController();
  late final Future<Rows> branches = sb.from('branches').select().order('name').then((r) => List<Map<String, dynamic>>.from(r));
  @override
  Widget build(BuildContext c) => FutureBuilder<Rows>(
        future: branches,
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final bs = s.data!;
          branch ??= bs.isEmpty ? null : bs.first['id'] as String;
          return ListView(padding: const EdgeInsets.all(16), children: [
            DropdownButtonFormField<String>(
              value: branch,
              decoration: InputDecoration(labelText: t('branch')),
              items: [for (final b in bs) DropdownMenuItem(value: b['id'] as String, child: Text('${b['name']}'))],
              onChanged: (v) => setState(() => branch = v),
            ),
            SwitchListTile(title: Text(t('priority')), value: prio, onChanged: (v) => setState(() => prio = v)),
            SwitchListTile(title: Text(t('remote')), value: remote, onChanged: (v) => setState(() => remote = v)),
            TextField(controller: phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'No. HP untuk notifikasi (opsional)')),
            const SizedBox(height: 12),
            if (branch != null)
              FutureBuilder(
                key: ValueKey(branch),
                future: sb.from('services').select().eq('branch_id', branch!).eq('active', true).order('name'),
                builder: (c, s) => Column(children: [
                  for (final sv in (s.data ?? []) as List)
                    Card(
                      child: ListTile(
                        title: Text('${sv['name']}'),
                        subtitle: Text('~${(sv['avg_service_sec'] / 60).round()} menit / layanan'),
                        trailing: const Icon(Icons.confirmation_number_outlined),
                        onTap: () async {
                          final r = await run(c, sb.rpc('issue_ticket', params: {
                            'p_branch': branch, 'p_service': sv['id'], 'p_priority': prio ? 1 : 0,
                            'p_channel': remote ? 'remote' : 'qr', 'p_phone': phone.text.isEmpty ? null : phone.text,
                          }));
                          if (r != null) toast(c, 'Tiket ${r['number']} terbit. Lihat tab Tiket Saya.');
                        },
                      ),
                    ),
                ]),
              ),
          ]);
        },
      );
}

class MyTicket extends StatefulWidget {
  const MyTicket({super.key});
  @override
  State<MyTicket> createState() => _MyState();
}

class _MyState extends State<MyTicket> {
  final rated = <String>{};
  late final stream = sb.from('tickets').stream(primaryKey: ['id']).eq('customer_id', sb.auth.currentUser!.id);
  @override
  Widget build(BuildContext c) => StreamBuilder<Rows>(
        stream: stream,
        builder: (c, s) {
          final ts = [...?s.data]..sort((a, b) => '${b['issued_at']}'.compareTo('${a['issued_at']}'));
          if (ts.isEmpty) return Center(child: Text(t('none')));
          final k = ts.first;
          final st = k['status'];
          return ListView(padding: const EdgeInsets.all(16), children: [
            StreamBuilder<Rows>(
              stream: sb.from('branches').stream(primaryKey: ['id']).eq('id', k['branch_id']),
              builder: (c, b) => (b.data?.firstOrNull?['paused'] == true)
                  ? Card(color: Colors.red.shade100, child: ListTile(leading: const Icon(Icons.warning), title: Text(t('paused'))))
                  : const SizedBox(),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Text('${k['number']}', style: Theme.of(c).textTheme.displayLarge),
                  Chip(label: Text('$st')),
                  if (st == 'waiting') EtaLine(id: k['id']),
                  if (st == 'called' || st == 'serving') CounterLine(id: k['counter_id']),
                  if (st == 'waiting' && k['expires_at'] != null)
                    FilledButton.tonal(onPressed: () => run(c, sb.rpc('check_in', params: {'p_ticket': k['id']})), child: const Text('Saya sudah di lokasi (check-in)')),
                  if (st == 'waiting')
                    TextButton(onPressed: () => run(c, sb.rpc('cancel_ticket', params: {'p_ticket': k['id']})), child: Text(t('cancel'))),
                ]),
              ),
            ),
            if (st == 'completed' && !rated.contains(k['id']))
              Card(
                child: Column(children: [
                  const Padding(padding: EdgeInsets.all(12), child: Text('Bagaimana layanannya?')),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        icon: const Icon(Icons.star, color: Colors.amber),
                        onPressed: () async {
                          final r = await run(c, sb.from('surveys').insert({'ticket_id': k['id'], 'score': i}));
                          setState(() => rated.add(k['id']));
                          if (r == null) toast(c, 'Terima kasih!');
                        },
                      ),
                  ]),
                ]),
              ),
          ]);
        },
      );
}

class EtaLine extends StatelessWidget {
  final String id;
  const EtaLine({super.key, required this.id});
  @override
  Widget build(BuildContext c) => StreamBuilder<dynamic>(
        stream: poll<dynamic>(() async => await sb.rpc('eta', params: {'p_ticket': id})),
        builder: (c, s) {
          final e = s.data;
          if (e == null) return const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator());
          return Column(children: [
            Text('Posisi ${e['position']}  •  estimasi ${e['min']}–${e['max']} menit', style: Theme.of(c).textTheme.titleMedium),
            if ((e['ahead'] as int) <= 3)
              Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(8), color: Colors.amber.shade100, child: Text(t('soon'))),
          ]);
        },
      );
}

class CounterLine extends StatelessWidget {
  final String? id;
  const CounterLine({super.key, this.id});
  @override
  Widget build(BuildContext c) => id == null
      ? const SizedBox()
      : FutureBuilder(
          future: sb.from('counters').select('name').eq('id', id!).single(),
          builder: (c, s) => Text('${t('now')} ${s.data?['name'] ?? ''}', style: Theme.of(c).textTheme.titleLarge),
        );
}

// ---------------- Agent ----------------
class AgentPage extends StatefulWidget {
  final String branch;
  const AgentPage({super.key, required this.branch});
  @override
  State<AgentPage> createState() => _AgentState();
}

class _AgentState extends State<AgentPage> {
  String? counter;
  late final cs = sb.from('counters').stream(primaryKey: ['id']).eq('branch_id', widget.branch).order('name');
  late final ts = sb.from('tickets').stream(primaryKey: ['id']).eq('branch_id', widget.branch);

  Future<void> act(String fn, Map<String, dynamic> p) async {
    final r = await run(context, sb.rpc(fn, params: p));
    if (r != null && fn == 'recall_ticket') toast(context, 'Panggilan ke-${r['recall_count']}');
  }

  @override
  Widget build(BuildContext c) => StreamBuilder<Rows>(
        stream: cs,
        builder: (c, a) {
          final counters = a.data ?? [];
          if (counters.isEmpty) return const Center(child: Text('Belum ada counter'));
          final cid = counter ?? counters.first['id'] as String;
          final me = counters.firstWhere((x) => x['id'] == cid, orElse: () => counters.first);
          return StreamBuilder<Rows>(
            stream: ts,
            builder: (c, b) {
              final all = b.data ?? [];
              final cur = all.where((x) => x['counter_id'] == cid && (x['status'] == 'called' || x['status'] == 'serving')).firstOrNull;
              final wait = all.where((x) => x['status'] == 'waiting').toList()
                ..sort((p, q) => (q['priority'] as int) != (p['priority'] as int)
                    ? (q['priority'] as int).compareTo(p['priority'] as int)
                    : '${p['issued_at']}'.compareTo('${q['issued_at']}'));
              return Scaffold(
                floatingActionButton: FloatingActionButton.extended(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Walk-in'),
                  onPressed: () async {
                    final sv = await sb.from('services').select().eq('branch_id', widget.branch).eq('active', true);
                    final x = await pick(c, 'Layanan walk-in', List<Map<String, dynamic>>.from(sv));
                    if (x != null && c.mounted) {
                      final r = await run(c, sb.rpc('issue_ticket', params: {'p_branch': widget.branch, 'p_service': x['id'], 'p_channel': 'walkin'}));
                      if (r != null && c.mounted) toast(c, 'Tiket ${r['number']}');
                    }
                  },
                ),
                body: ListView(padding: const EdgeInsets.all(16), children: [
                  DropdownButtonFormField<String>(
                    value: cid,
                    decoration: const InputDecoration(labelText: 'Counter'),
                    items: [for (final x in counters) DropdownMenuItem(value: x['id'] as String, child: Text('${x['name']} (${x['status']})'))],
                    onChanged: (v) => setState(() => counter = v),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final s in ['available', 'break', 'offline'])
                      ChoiceChip(label: Text(s), selected: me['status'] == s, onSelected: (_) => act('set_counter', {'p_counter': cid, 'p_status': s})),
                  ]),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: cur == null
                          ? Column(children: [
                              Text('Tidak ada tiket aktif', style: Theme.of(c).textTheme.titleMedium),
                              const SizedBox(height: 8),
                              FilledButton.icon(icon: const Icon(Icons.campaign), label: Text(t('next')), onPressed: () => act('call_next', {'p_counter': cid})),
                            ])
                          : Column(children: [
                              Text('${cur['number']}', style: Theme.of(c).textTheme.displayMedium),
                              Text('${cur['status']}  •  recall ${cur['recall_count']}/3'),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, children: [
                                if (cur['status'] == 'called') ...[
                                  FilledButton(onPressed: () => act('start_service', {'p_ticket': cur['id']}), child: Text(t('start'))),
                                  OutlinedButton(onPressed: () => act('recall_ticket', {'p_ticket': cur['id']}), child: Text(t('recall'))),
                                  OutlinedButton(onPressed: () => act('no_show', {'p_ticket': cur['id']}), child: Text(t('noshow'))),
                                ],
                                if (cur['status'] == 'serving')
                                  FilledButton(
                                    onPressed: () async {
                                      final r = await ask(c, 'Selesaikan tiket', ['Kode hasil (outcome)', 'Catatan']);
                                      if (r != null) act('complete_ticket', {'p_ticket': cur['id'], 'p_outcome': r[0].isEmpty ? null : r[0], 'p_notes': r[1].isEmpty ? null : r[1]});
                                    },
                                    child: Text(t('done')),
                                  ),
                                OutlinedButton(
                                  onPressed: () async {
                                    final sv = await sb.from('services').select().eq('branch_id', widget.branch).eq('active', true);
                                    final x = await pick(c, 'Pindah ke layanan', List<Map<String, dynamic>>.from(sv));
                                    if (x != null) act('transfer_ticket', {'p_ticket': cur['id'], 'p_service': x['id']});
                                  },
                                  child: Text(t('transfer')),
                                ),
                              ]),
                            ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('${t('waiting')} (${wait.length})', style: Theme.of(c).textTheme.titleMedium),
                  for (final w in wait.take(20))
                    ListTile(
                      dense: true,
                      leading: Icon(w['priority'] > 0 ? Icons.star : Icons.confirmation_number_outlined),
                      title: Text('${w['number']}'),
                      subtitle: Text('${w['channel']}'),
                    ),
                ]),
              );
            },
          );
        },
      );
}

// ---------------- Supervisor / Manager ----------------
class Stat extends StatelessWidget {
  final String label;
  final Object? v;
  const Stat(this.label, this.v, {super.key});
  @override
  Widget build(BuildContext c) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${v ?? '-'}', style: Theme.of(c).textTheme.headlineMedium),
            Text(label, style: Theme.of(c).textTheme.bodySmall),
          ]),
        ),
      );
}

class LivePage extends StatelessWidget {
  final String branch;
  const LivePage({super.key, required this.branch});
  @override
  Widget build(BuildContext c) => ListView(padding: const EdgeInsets.all(12), children: [
        StreamBuilder<dynamic>(
          stream: poll<dynamic>(() async => await sb.rpc('branch_metrics', params: {'p_branch': branch})),
          builder: (c, s) {
            final m = (s.data as Map?) ?? {};
            return GridView.count(
              crossAxisCount: 3, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.3,
              children: [
                Stat('Menunggu', m['waiting']), Stat('Dilayani', m['serving']), Stat('Selesai', m['served']),
                Stat('Avg wait (mnt)', m['avg_wait_min']), Stat('No-show %', m['no_show_pct']), Stat('Counter aktif', m['active_counters']),
              ],
            );
          },
        ),
        StreamBuilder<Rows>(
          stream: sb.from('branches').stream(primaryKey: ['id']).eq('id', branch),
          builder: (c, s) {
            final paused = s.data?.firstOrNull?['paused'] == true;
            return SwitchListTile(
              secondary: const Icon(Icons.emergency),
              title: const Text('Mode darurat (jeda antrian)'),
              value: paused,
              onChanged: (v) => run(c, sb.from('branches').update({'paused': v}).eq('id', branch)),
            );
          },
        ),
        const Divider(),
        StreamBuilder<Rows>(
          stream: sb.from('counters').stream(primaryKey: ['id']).eq('branch_id', branch).order('name'),
          builder: (c, s) => Column(children: [
            for (final x in s.data ?? [])
              SwitchListTile(
                title: Text('${x['name']}'),
                subtitle: Text('${x['status']}'),
                value: x['status'] != 'closed',
                onChanged: (v) => run(c, sb.rpc('set_counter', params: {'p_counter': x['id'], 'p_status': v ? 'available' : 'closed'})),
              ),
          ]),
        ),
      ]);
}

class AlertsPage extends StatelessWidget {
  final String branch;
  const AlertsPage({super.key, required this.branch});
  @override
  Widget build(BuildContext c) => StreamBuilder<Rows>(
        stream: sb.from('alerts').stream(primaryKey: ['id']).eq('branch_id', branch),
        builder: (c, s) {
          final xs = [...?s.data]..sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
          if (xs.isEmpty) return const Center(child: Text('Tidak ada alert'));
          return ListView(children: [
            for (final a in xs)
              ListTile(
                leading: Icon(a['severity'] == 'critical' ? Icons.error : Icons.warning_amber, color: a['severity'] == 'critical' ? Colors.red : Colors.orange),
                title: Text('${a['message']}'),
                subtitle: Text('${a['status']}${a['escalated'] == true ? ' • eskalasi' : ''} • ${a['created_at']}'.replaceFirst('T', ' ').split('.').first),
                trailing: a['status'] == 'open'
                    ? TextButton(
                        onPressed: () => run(c, sb.from('alerts').update({'status': 'acknowledged', 'acked_by': sb.auth.currentUser!.id, 'acked_at': DateTime.now().toUtc().toIso8601String()}).eq('id', a['id'])),
                        child: const Text('Ack'))
                    : null,
              ),
          ]);
        },
      );
}

class RegionalPage extends StatefulWidget {
  const RegionalPage({super.key});
  @override
  State<RegionalPage> createState() => _RegionalState();
}

class _RegionalState extends State<RegionalPage> {
  int days = 7;
  @override
  Widget build(BuildContext c) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<int>(
            segments: const [ButtonSegment(value: 1, label: Text('1 hari')), ButtonSegment(value: 7, label: Text('7 hari')), ButtonSegment(value: 30, label: Text('30 hari'))],
            selected: {days},
            onSelectionChanged: (v) => setState(() => days = v.first),
          ),
        ),
        Expanded(
          child: FutureBuilder(
            key: ValueKey(days),
            future: sb.rpc('branch_compare', params: {'p_days': days}),
            builder: (c, s) {
              if (!s.hasData) return const Center(child: CircularProgressIndicator());
              final rows = List<Map<String, dynamic>>.from(s.data as List);
              final maxW = rows.fold<num>(1, (m, r) => (r['avg_wait'] as num) > m ? r['avg_wait'] as num : m);
              return ListView(padding: const EdgeInsets.all(8), children: [
                for (var i = 0; i < rows.length; i++)
                  Card(
                    color: (rows[i]['sla_pct'] as num) >= 90 ? Colors.green.shade50 : (rows[i]['sla_pct'] as num) >= 75 ? Colors.amber.shade50 : Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('#${i + 1}  ${rows[i]['name']}', style: Theme.of(c).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(value: (rows[i]['avg_wait'] as num) / maxW),
                        const SizedBox(height: 6),
                        Text('Tiket ${rows[i]['ticket_count']} • avg ${rows[i]['avg_wait']} mnt • p90 ${rows[i]['p90_wait']} mnt\n'
                            'SLA ${rows[i]['sla_pct']}% • no-show ${rows[i]['no_show_pct']}% • CSAT ${rows[i]['csat']}'),
                      ]),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]);
}

// ---------------- Admin ----------------
class ServicesAdmin extends StatelessWidget {
  final String branch;
  const ServicesAdmin({super.key, required this.branch});
  @override
  Widget build(BuildContext c) => Scaffold(
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () async {
            final r = await ask(c, 'Layanan baru', ['Nama', 'Kode (1 huruf)', 'Rata-rata layanan (detik)']);
            if (r != null && c.mounted) run(c, sb.from('services').insert({'branch_id': branch, 'name': r[0], 'code': r[1].toUpperCase(), 'avg_service_sec': int.tryParse(r[2]) ?? 300}));
          },
        ),
        body: StreamBuilder<Rows>(
          stream: sb.from('services').stream(primaryKey: ['id']).eq('branch_id', branch),
          builder: (c, s) => ListView(children: [
            for (final x in s.data ?? [])
              SwitchListTile(title: Text('${x['code']} — ${x['name']}'), subtitle: Text('${x['avg_service_sec']} detik'), value: x['active'] == true,
                  onChanged: (v) => run(c, sb.from('services').update({'active': v}).eq('id', x['id']))),
          ]),
        ),
      );
}

class RulesAdmin extends StatelessWidget {
  final String branch;
  const RulesAdmin({super.key, required this.branch});
  @override
  Widget build(BuildContext c) => Scaffold(
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () async {
            final r = await ask(c, 'Alert rule', ['Metrik: wait_over / queue_over / idle_counter / no_show_rate', 'Batas', 'Eskalasi (menit)']);
            if (r != null && c.mounted) run(c, sb.from('alert_rules').insert({'branch_id': branch, 'metric': r[0], 'threshold': num.tryParse(r[1]) ?? 10, 'escalate_after_min': int.tryParse(r[2]) ?? 10}));
          },
        ),
        body: StreamBuilder<Rows>(
          stream: sb.from('alert_rules').stream(primaryKey: ['id']).eq('branch_id', branch),
          builder: (c, s) => ListView(children: [
            for (final x in s.data ?? [])
              SwitchListTile(title: Text('${x['metric']} > ${x['threshold']}'), subtitle: Text('eskalasi ${x['escalate_after_min']} mnt'), value: x['active'] == true,
                  onChanged: (v) => run(c, sb.from('alert_rules').update({'active': v}).eq('id', x['id']))),
          ]),
        ),
      );
}

class UsersAdmin extends StatefulWidget {
  const UsersAdmin({super.key});
  @override
  State<UsersAdmin> createState() => _UsersState();
}

class _UsersState extends State<UsersAdmin> {
  Future<(Rows, Rows)> load() async {
    final u = await sb.from('profiles').select().order('full_name');
    final b = await sb.from('branches').select('id,name').order('name');
    return (List<Map<String, dynamic>>.from(u), List<Map<String, dynamic>>.from(b));
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<(Rows, Rows)>(
        future: load(),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final (users, bs) = s.data!;
          return ListView(children: [
            for (final u in users)
              ListTile(
                title: Text('${u['full_name']}'),
                subtitle: Text('${u['role']} • ${bs.where((b) => b['id'] == u['branch_id']).firstOrNull?['name'] ?? 'semua/tanpa cabang'}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.badge),
                    onSelected: (v) async { await run(c, sb.from('profiles').update({'role': v}).eq('id', u['id'])); setState(() {}); },
                    itemBuilder: (_) => [for (final r in ['customer', 'agent', 'supervisor', 'manager', 'admin']) PopupMenuItem(value: r, child: Text(r))],
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.store),
                    onSelected: (v) async { await run(c, sb.from('profiles').update({'branch_id': v}).eq('id', u['id'])); setState(() {}); },
                    itemBuilder: (_) => [for (final b in bs) PopupMenuItem(value: b['id'] as String, child: Text('${b['name']}'))],
                  ),
                ]),
              ),
          ]);
        },
      );
}

class AuditPage extends StatelessWidget {
  const AuditPage({super.key});
  @override
  Widget build(BuildContext c) => FutureBuilder(
        future: sb.from('audit_log').select().order('created_at', ascending: false).limit(100),
        builder: (c, s) => ListView(children: [
          for (final a in (s.data ?? []) as List)
            ExpansionTile(
              title: Text('${a['action']} ${a['table_name']}'),
              subtitle: Text('${a['created_at']}'.replaceFirst('T', ' ').split('.').first),
              children: [Padding(padding: const EdgeInsets.all(12), child: SelectableText('before: ${a['before']}\n\nafter: ${a['after']}'))],
            ),
        ]),
      );
}

// ---------------- Display screen ----------------
class DisplayPage extends StatelessWidget {
  const DisplayPage({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        appBar: AppBar(title: const Text('Layar Antrian'), actions: [
          TextButton(onPressed: () => lang.value = lang.value == 'id' ? 'en' : 'id', child: Text(lang.value.toUpperCase())),
        ]),
        body: BranchScope(builder: (id) => DisplayBoard(branch: id)),
      );
}

class DisplayBoard extends StatefulWidget {
  final String branch;
  const DisplayBoard({super.key, required this.branch});
  @override
  State<DisplayBoard> createState() => _BoardState();
}

class _BoardState extends State<DisplayBoard> {
  final tts = FlutterTts();
  final spoken = <String>{};
  Rows rows = [];
  bool first = true;
  StreamSubscription? sub;
  Timer? hb;

  @override
  void initState() {
    super.initState();
    hb = beat();
    sub = poll<List>(() async => await sb.from('display_board').select().eq('branch_id', widget.branch), 2).listen((r) {
      rows = List<Map<String, dynamic>>.from(r);
      for (final x in rows.where((x) => x['status'] == 'called')) {
        final k = '${x['id']}${x['called_at']}';
        if (spoken.add(k) && !first) speak('${x['number']}', '${x['counter_name']}');
      }
      first = false;
      if (mounted) setState(() {});
    });
  }

  Future<void> speak(String n, String ctr) async {
    final id = lang.value == 'id';
    await tts.setLanguage(id ? 'id-ID' : 'en-US');
    await tts.speak(id ? 'Nomor antrian $n, silakan menuju $ctr' : 'Ticket $n, please proceed to $ctr');
  }

  @override
  void dispose() { hb?.cancel(); sub?.cancel(); tts.stop(); super.dispose(); }

  @override
  Widget build(BuildContext c) {
    final now = rows.where((x) => x['status'] == 'called' || x['status'] == 'serving').toList();
    final next = rows.where((x) => x['status'] == 'waiting').toList()
      ..sort((a, b) => (b['priority'] as int) != (a['priority'] as int) ? (b['priority'] as int).compareTo(a['priority'] as int) : '${a['issued_at']}'.compareTo('${b['issued_at']}'));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Expanded(
          child: Wrap(spacing: 16, runSpacing: 16, children: [
            for (final x in now)
              SizedBox(
                width: 220,
                child: Card(
                  color: x['status'] == 'called' ? Colors.amber.shade100 : Colors.green.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(children: [
                      Text('${x['number']}', style: Theme.of(c).textTheme.displayMedium),
                      Text('${x['counter_name']}', style: Theme.of(c).textTheme.titleLarge),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
        Text(lang.value == 'id' ? 'Berikutnya' : 'Next', style: Theme.of(c).textTheme.titleMedium),
        Wrap(spacing: 8, children: [for (final x in next.take(8)) Chip(label: Text('${x['number']}'))]),
      ]),
    );
  }
}

// ---------------- Kiosk ----------------
class KioskPage extends StatefulWidget {
  const KioskPage({super.key});
  @override
  State<KioskPage> createState() => _KioskState();
}

class _KioskState extends State<KioskPage> {
  bool big = false;
  Timer? hb;
  @override
  void initState() {
    super.initState();
    hb = beat();
    if (sb.auth.currentUser == null) sb.auth.signInAnonymously();
  }

  @override
  void dispose() { hb?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext c) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(big ? 1.5 : 1.0)),
        child: Scaffold(
          appBar: AppBar(title: const Text('Ambil Nomor Antrian'), actions: [
            IconButton(tooltip: 'Mode aksesibilitas', icon: Icon(big ? Icons.zoom_out : Icons.accessibility_new), onPressed: () => setState(() => big = !big)),
            TextButton(onPressed: () => lang.value = lang.value == 'id' ? 'en' : 'id', child: Text(lang.value.toUpperCase())),
          ]),
          body: BranchScope(
            builder: (b) => FutureBuilder(
              future: sb.from('services').select().eq('branch_id', b).eq('active', true).order('name'),
              builder: (c, s) => GridView.count(
                crossAxisCount: 2, padding: const EdgeInsets.all(16), mainAxisSpacing: 16, crossAxisSpacing: 16,
                children: [
                  for (final sv in (s.data ?? []) as List)
                    FilledButton(
                      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      onPressed: () async {
                        final r = await run(c, sb.rpc('issue_ticket', params: {'p_branch': b, 'p_service': sv['id'], 'p_channel': 'kiosk'}));
                        if (r != null && c.mounted) {
                          await showDialog(context: c, builder: (d) => AlertDialog(
                            title: Text(lang.value == 'id' ? 'Nomor Anda' : 'Your number', textAlign: TextAlign.center),
                            content: Text('${r['number']}', style: Theme.of(c).textTheme.displayLarge, textAlign: TextAlign.center),
                            actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))]));
                        }
                      },
                      child: Text('${sv['code']}\n${sv['name']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22)),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

// ---------------- Forecast, Device, Webhook, MFA ----------------
class ForecastPage extends StatelessWidget {
  final String branch;
  const ForecastPage({super.key, required this.branch});
  @override
  Widget build(BuildContext c) => FutureBuilder(
        future: sb.rpc('forecast', params: {'p_branch': branch}),
        builder: (c, s) {
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final rows = List<Map<String, dynamic>>.from(s.data as List);
          final mx = rows.fold<num>(1, (m, r) => (r['expected'] as num) > m ? r['expected'] as num : m);
          return ListView(padding: const EdgeInsets.all(12), children: [
            const Text('Prediksi tiket per jam & rekomendasi jumlah counter (8 jam ke depan)'),
            for (final r in rows)
              ListTile(
                title: Text('${DateTime.parse(r['hour_ts']).toLocal().hour.toString().padLeft(2, '0')}:00  •  ${r['expected']} tiket  •  ${r['counters_needed']} counter'),
                subtitle: LinearProgressIndicator(value: (r['expected'] as num) / mx),
              ),
          ]);
        },
      );
}

class DevicesAdmin extends StatelessWidget {
  final String branch;
  const DevicesAdmin({super.key, required this.branch});
  @override
  Widget build(BuildContext c) => Scaffold(
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () async {
            final r = await ask(c, 'Device baru', ['Nama', 'Jenis: kiosk / display / printer']);
            if (r != null && c.mounted) run(c, sb.from('devices').insert({'branch_id': branch, 'name': r[0], 'kind': r[1]}));
          },
        ),
        body: StreamBuilder<dynamic>(
          stream: poll<dynamic>(() async => await sb.from('devices').select().eq('branch_id', branch).order('name'), 10),
          builder: (c, s) => ListView(children: [
            for (final d in (s.data ?? []) as List)
              Builder(builder: (_) {
                final seen = d['last_seen'] == null ? null : DateTime.parse(d['last_seen']);
                final on = seen != null && DateTime.now().toUtc().difference(seen).inMinutes < 2;
                return ListTile(
                  leading: Icon(Icons.circle, color: on ? Colors.green : Colors.red, size: 14),
                  title: Text('${d['name']} (${d['kind']})'),
                  subtitle: SelectableText('DEVICE_ID=${d['id']}'),
                );
              }),
          ]),
        ),
      );
}

class WebhooksAdmin extends StatelessWidget {
  const WebhooksAdmin({super.key});
  @override
  Widget build(BuildContext c) => Scaffold(
        floatingActionButton: FloatingActionButton(
          child: const Icon(Icons.add),
          onPressed: () async {
            final r = await ask(c, 'Webhook', ['URL endpoint', 'Event (pisah koma, kosong = semua)']);
            if (r != null && c.mounted) run(c, sb.from('webhooks').insert({'url': r[0], 'events': r[1].isEmpty ? [] : r[1].split(',').map((e) => e.trim()).toList()}));
          },
        ),
        body: StreamBuilder<Rows>(
          stream: sb.from('webhooks').stream(primaryKey: ['id']),
          builder: (c, s) => ListView(children: [
            for (final w in s.data ?? [])
              ExpansionTile(
                title: Text('${w['url']}'),
                subtitle: Text('${(w['events'] as List).isEmpty ? 'semua event' : (w['events'] as List).join(', ')}'),
                children: [
                  SelectableText('Secret (HMAC-SHA256, header X-QueueFlow-Signature): ${w['secret']}'),
                  SwitchListTile(title: const Text('Aktif'), value: w['active'] == true, onChanged: (v) => run(c, sb.from('webhooks').update({'active': v}).eq('id', w['id']))),
                ],
              ),
          ]),
        ),
      );
}

class MfaPage extends StatefulWidget {
  const MfaPage({super.key});
  @override
  State<MfaPage> createState() => _MfaState();
}

class _MfaState extends State<MfaPage> {
  String? factor, secret;
  final code = TextEditingController();
  @override
  Widget build(BuildContext c) => ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Autentikasi dua langkah (TOTP) untuk akun admin'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () async {
            final r = await run(c, sb.auth.mfa.enroll(factorType: FactorType.totp));
            if (r != null) setState(() { factor = r.id; secret = r.totp?.secret; });
          },
          child: const Text('Aktifkan MFA'),
        ),
        if (secret != null) ...[
          const SizedBox(height: 12),
          const Text('Masukkan secret ini ke Google Authenticator / Authy:'),
          SelectableText(secret!, style: Theme.of(c).textTheme.titleLarge),
          TextField(controller: code, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kode 6 digit')),
          FilledButton(
            onPressed: () async {
              final ch = await run(c, sb.auth.mfa.challenge(factorId: factor!));
              if (ch == null) return;
              final v = await run(c, sb.auth.mfa.verify(factorId: factor!, challengeId: ch.id, code: code.text.trim()));
              if (v != null && c.mounted) { toast(c, 'MFA aktif'); setState(() => secret = null); }
            },
            child: const Text('Verifikasi'),
          ),
        ],
      ]);
}
