-- QueueFlow | jalankan sekali di Supabase SQL Editor
-- Aktifkan juga: Auth > Providers > Anonymous sign-ins (untuk pelanggan)
create extension if not exists pgcrypto;

create type user_role as enum ('customer','agent','supervisor','manager','admin');
create type ticket_status as enum ('waiting','called','serving','completed','no_show','cancelled','expired');

create table branches(
  id uuid primary key default gen_random_uuid(), name text not null, address text,
  open_time time default '07:00', close_time time default '21:00', tz text default 'Asia/Jakarta',
  capacity int default 200, accepts_remote bool default true, paused bool default false,
  sla_minutes int default 15, created_at timestamptz default now());
create table services(
  id uuid primary key default gen_random_uuid(), branch_id uuid references branches on delete cascade,
  name text not null, code text not null, avg_service_sec int default 300, active bool default true);
create table counters(
  id uuid primary key default gen_random_uuid(), branch_id uuid references branches on delete cascade,
  name text not null, service_ids uuid[] default '{}',
  status text default 'offline' check (status in ('available','busy','break','offline','closed')),
  agent_id uuid references auth.users, last_status_at timestamptz default now());
create table profiles(
  id uuid primary key references auth.users on delete cascade, full_name text,
  role user_role default 'customer', branch_id uuid references branches, phone text);
create table tickets(
  id uuid primary key default gen_random_uuid(), branch_id uuid references branches on delete cascade,
  service_id uuid references services, number text not null, priority int default 0,
  channel text default 'qr', status ticket_status default 'waiting', customer_id uuid,
  issued_at timestamptz default now(), called_at timestamptz, started_at timestamptz, ended_at timestamptz,
  counter_id uuid references counters, recall_count int default 0, outcome text, notes text,
  expires_at timestamptz, ticket_date date);
create index on tickets(branch_id, status, issued_at);
create table ticket_contacts(ticket_id uuid primary key references tickets on delete cascade, phone text not null);
alter table ticket_contacts enable row level security;
create table queue_events(
  id bigserial primary key, ticket_id uuid, branch_id uuid, type text, actor uuid,
  payload jsonb default '{}', created_at timestamptz default now());
create table alert_rules(
  id uuid primary key default gen_random_uuid(), branch_id uuid references branches on delete cascade,
  metric text check (metric in ('wait_over','queue_over','idle_counter','no_show_rate')),
  threshold numeric not null, escalate_after_min int default 10, active bool default true);
create table alerts(
  id uuid primary key default gen_random_uuid(), rule_id uuid references alert_rules on delete cascade,
  branch_id uuid, message text, severity text default 'warning',
  status text default 'open', escalated bool default false, created_at timestamptz default now(),
  acked_by uuid, acked_at timestamptz, resolved_at timestamptz);
create table surveys(
  id uuid primary key default gen_random_uuid(), ticket_id uuid unique references tickets,
  score int check (score between 1 and 5), comment text, created_at timestamptz default now());
create table audit_log(
  id bigserial primary key, actor uuid, action text, table_name text, row_id text,
  before jsonb, after jsonb, created_at timestamptz default now());

-- helper
create or replace function my_role() returns user_role language sql stable security definer set search_path=public as
$$ select role from profiles where id=auth.uid() $$;
create or replace function is_staff(b uuid) returns boolean language sql stable security definer set search_path=public as
$$ select exists(select 1 from profiles where id=auth.uid()
   and (role in ('manager','admin') or (role in ('agent','supervisor') and branch_id=b))) $$;

-- profil otomatis
create or replace function handle_new_user() returns trigger language plpgsql security definer set search_path=public as
$$ begin insert into profiles(id,full_name) values(new.id, split_part(coalesce(new.email,'tamu'),'@',1)); return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- audit immutable
create or replace function audit() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into audit_log(actor,action,table_name,row_id,before,after) values(auth.uid(),tg_op,tg_table_name,
    coalesce(to_jsonb(new)->>'id',to_jsonb(old)->>'id'),
    case when tg_op<>'INSERT' then to_jsonb(old) end, case when tg_op<>'DELETE' then to_jsonb(new) end);
  return coalesce(new,old);
end $$;
create trigger a1 after insert or update or delete on branches for each row execute function audit();
create trigger a2 after insert or update or delete on services for each row execute function audit();
create trigger a3 after insert or update or delete on alert_rules for each row execute function audit();
create trigger a4 after update on profiles for each row execute function audit();
create or replace function audit_lock() returns trigger language plpgsql as $$ begin raise exception 'audit_log immutable'; end $$;
create trigger audit_immutable before update or delete on audit_log for each row execute function audit_lock();

-- event log (append-only)
create or replace function log_ticket_event() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into queue_events(ticket_id,branch_id,type,actor,payload) values(new.id,new.branch_id,'ticket_issued',auth.uid(),
      jsonb_build_object('channel',new.channel,'priority',new.priority,'service_id',new.service_id));
  elsif new.status is distinct from old.status then
    insert into queue_events(ticket_id,branch_id,type,actor,payload) values(new.id,new.branch_id,'ticket_'||new.status,auth.uid(),
      jsonb_build_object('counter_id',new.counter_id,'recall_count',new.recall_count,'outcome',new.outcome));
  end if;
  return new;
end $$;
create trigger t_events after insert or update on tickets for each row execute function log_ticket_event();

-- terbitkan tiket
create or replace function issue_ticket(p_branch uuid,p_service uuid,p_priority int default 0,p_channel text default 'qr',p_phone text default null)
returns tickets language plpgsql security definer set search_path=public as $$
declare b branches; s services; n int; d date; t tickets; lt time;
begin
  select * into b from branches where id=p_branch;
  select * into s from services where id=p_service and branch_id=p_branch and active;
  if b.id is null or s.id is null then raise exception 'Cabang/layanan tidak valid'; end if;
  if b.paused then raise exception 'Antrian sedang dijeda (mode darurat)'; end if;
  if p_channel='walkin' and not is_staff(p_branch) then raise exception 'Akses ditolak'; end if;
  if p_channel='remote' and not b.accepts_remote then raise exception 'Cabang tidak menerima tiket remote'; end if;
  lt := (now() at time zone b.tz)::time; d := (now() at time zone b.tz)::date;
  if lt < b.open_time or lt > b.close_time then raise exception 'Cabang sedang tutup'; end if;
  if (select count(*) from tickets where branch_id=p_branch and status='waiting') >= b.capacity then raise exception 'Antrian penuh'; end if;
  perform pg_advisory_xact_lock(hashtext(p_service::text));
  select count(*)+1 into n from tickets where service_id=p_service and ticket_date=d;
  insert into tickets(branch_id,service_id,number,priority,channel,customer_id,ticket_date,expires_at)
  values(p_branch,p_service,s.code||lpad(n::text,3,'0'),p_priority,p_channel,
    case when p_channel='walkin' then null else auth.uid() end,d,
    case when p_channel='remote' then now()+interval '30 minutes' end) returning * into t;
  if p_phone is not null and p_phone<>'' then insert into ticket_contacts values(t.id,p_phone); end if;
  return t;
end $$;

-- ETA = rata2 durasi layanan x tiket di depan / counter aktif, ditampilkan sebagai range
create or replace function eta(p_ticket uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare t tickets; ahead int; act int; avg_s numeric; m numeric;
begin
  select * into t from tickets where id=p_ticket and (customer_id=auth.uid() or is_staff(branch_id));
  if t.id is null then return null; end if;
  select count(*) into ahead from tickets x where x.branch_id=t.branch_id and x.service_id=t.service_id and x.status='waiting'
    and x.id<>t.id and (x.priority>t.priority or (x.priority=t.priority and x.issued_at<t.issued_at));
  select count(*) into act from counters c where c.branch_id=t.branch_id and c.status in ('available','busy')
    and (cardinality(c.service_ids)=0 or t.service_id=any(c.service_ids));
  select coalesce(avg(sec),(select avg_service_sec from services where id=t.service_id)) into avg_s from
    (select extract(epoch from ended_at-started_at) sec from tickets where service_id=t.service_id and status='completed'
     and started_at is not null order by ended_at desc limit 20) q;
  m := avg_s*(ahead+1)/greatest(act,1)/60;
  return jsonb_build_object('position',ahead+1,'ahead',ahead,'active_counters',act,'min',floor(m*0.8),'max',ceil(m*1.25));
end $$;

-- panggil berikutnya: prioritas + proteksi starvation (reguler >15 mnt didahulukan)
create or replace function call_next(p_counter uuid) returns tickets language plpgsql security definer set search_path=public as $$
declare c counters; t tickets;
begin
  select * into c from counters where id=p_counter for update;
  if c.id is null or not is_staff(c.branch_id) then raise exception 'Akses ditolak'; end if;
  if c.status='busy' then raise exception 'Selesaikan tiket saat ini dulu'; end if;
  if c.status<>'available' then raise exception 'Counter belum Available'; end if;
  if (select paused from branches where id=c.branch_id) then raise exception 'Antrian sedang dijeda'; end if;
  select * into t from tickets x where x.branch_id=c.branch_id and x.status='waiting'
    and (cardinality(c.service_ids)=0 or x.service_id=any(c.service_ids))
    order by (x.priority=0 and x.issued_at<now()-interval '15 minutes') desc, x.priority desc, x.issued_at
    limit 1 for update skip locked;
  if t.id is null then raise exception 'Tidak ada antrian'; end if;
  update tickets set status='called',counter_id=c.id,called_at=now(),recall_count=0 where id=t.id returning * into t;
  update counters set status='busy',agent_id=auth.uid(),last_status_at=now() where id=c.id;
  return t;
end $$;

create or replace function recall_ticket(p_ticket uuid) returns tickets language plpgsql security definer set search_path=public as $$
declare t tickets;
begin
  select * into t from tickets where id=p_ticket and status='called' for update;
  if t.id is null or not is_staff(t.branch_id) then raise exception 'Tiket tidak valid'; end if;
  if t.recall_count+1>=3 then
    update tickets set status='no_show',recall_count=3,ended_at=now() where id=t.id returning * into t;
    update counters set status='available',last_status_at=now() where id=t.counter_id;
  else
    update tickets set recall_count=recall_count+1,called_at=now() where id=t.id returning * into t;
  end if;
  return t;
end $$;

create or replace function no_show(p_ticket uuid) returns tickets language plpgsql security definer set search_path=public as $$
declare t tickets;
begin
  select * into t from tickets where id=p_ticket and status='called' for update;
  if t.id is null or not is_staff(t.branch_id) then raise exception 'Tiket tidak valid'; end if;
  update tickets set status='no_show',ended_at=now() where id=t.id returning * into t;
  update counters set status='available',last_status_at=now() where id=t.counter_id;
  return t;
end $$;

create or replace function start_service(p_ticket uuid) returns tickets language plpgsql security definer set search_path=public as $$
declare t tickets;
begin
  select * into t from tickets where id=p_ticket and status='called' for update;
  if t.id is null or not is_staff(t.branch_id) then raise exception 'Tiket tidak valid'; end if;
  update tickets set status='serving',started_at=now() where id=t.id returning * into t;
  return t;
end $$;

create or replace function complete_ticket(p_ticket uuid,p_outcome text default null,p_notes text default null)
returns tickets language plpgsql security definer set search_path=public as $$
declare t tickets;
begin
  select * into t from tickets where id=p_ticket and status='serving' for update;
  if t.id is null or not is_staff(t.branch_id) then raise exception 'Tiket tidak valid'; end if;
  update tickets set status='completed',ended_at=now(),outcome=p_outcome,notes=p_notes where id=t.id returning * into t;
  update counters set status='available',last_status_at=now() where id=t.counter_id;
  return t;
end $$;

-- transfer: masuk antrian layanan tujuan, issued_at asli dipertahankan
create or replace function transfer_ticket(p_ticket uuid,p_service uuid) returns tickets language plpgsql security definer set search_path=public as $$
declare t tickets;
begin
  select * into t from tickets where id=p_ticket and status in ('called','serving') for update;
  if t.id is null or not is_staff(t.branch_id) then raise exception 'Tiket tidak valid'; end if;
  if not exists(select 1 from services where id=p_service and branch_id=t.branch_id and active) then raise exception 'Layanan tujuan tidak valid'; end if;
  update counters set status='available',last_status_at=now() where id=t.counter_id;
  update tickets set status='waiting',service_id=p_service,counter_id=null,called_at=null,started_at=null,recall_count=0
    where id=t.id returning * into t;
  return t;
end $$;

create or replace function cancel_ticket(p_ticket uuid) returns tickets language plpgsql security definer set search_path=public as $$
declare t tickets;
begin
  select * into t from tickets where id=p_ticket and status='waiting' for update;
  if t.id is null or not (t.customer_id=auth.uid() or is_staff(t.branch_id)) then raise exception 'Tiket tidak bisa dibatalkan'; end if;
  update tickets set status='cancelled',ended_at=now() where id=t.id returning * into t;
  return t;
end $$;

create or replace function check_in(p_ticket uuid) returns tickets language plpgsql security definer set search_path=public as $$
declare t tickets;
begin
  update tickets set expires_at=null where id=p_ticket and customer_id=auth.uid() and status='waiting' returning * into t;
  if t.id is null then raise exception 'Tiket tidak valid'; end if;
  return t;
end $$;

create or replace function set_counter(p_counter uuid,p_status text) returns void language plpgsql security definer set search_path=public as $$
declare c counters;
begin
  select * into c from counters where id=p_counter for update;
  if c.id is null or not is_staff(c.branch_id) then raise exception 'Akses ditolak'; end if;
  if c.status='busy' then raise exception 'Counter sedang melayani'; end if;
  if p_status not in ('available','break','offline','closed') then raise exception 'Status tidak valid'; end if;
  update counters set status=p_status,last_status_at=now(),agent_id=case when p_status='available' then auth.uid() else agent_id end where id=p_counter;
end $$;

-- metrik live cabang (hari ini)
create or replace function branch_metrics(p_branch uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r jsonb;
begin
  if not is_staff(p_branch) then raise exception 'Akses ditolak'; end if;
  select jsonb_build_object(
    'waiting',count(*) filter (where status='waiting'),
    'serving',count(*) filter (where status in ('called','serving')),
    'served',count(*) filter (where status='completed'),
    'avg_wait_min',coalesce(round((avg(extract(epoch from called_at-issued_at)) filter (where called_at is not null)/60)::numeric,1),0),
    'no_show_pct',coalesce(round(100.0*count(*) filter (where status='no_show')/nullif(count(*),0),1),0),
    'active_counters',(select count(*) from counters where branch_id=p_branch and status in ('available','busy')))
  into r from tickets where branch_id=p_branch
    and issued_at>=date_trunc('day',now() at time zone 'Asia/Jakarta') at time zone 'Asia/Jakarta';
  return r;
end $$;

-- perbandingan antar cabang (manager/admin)
create or replace function branch_compare(p_days int default 7)
returns table(branch_id uuid,name text,ticket_count bigint,avg_wait numeric,p90_wait numeric,sla_pct numeric,no_show_pct numeric,csat numeric)
language sql stable security definer set search_path=public as $$
  select b.id,b.name,count(t.id),
    coalesce(round((avg(extract(epoch from t.called_at-t.issued_at))/60)::numeric,1),0),
    coalesce(round((percentile_cont(0.9) within group (order by extract(epoch from t.called_at-t.issued_at))/60)::numeric,1),0),
    coalesce(round(100.0*count(*) filter (where t.called_at-t.issued_at<=b.sla_minutes*interval '1 minute')/nullif(count(t.called_at),0),1),0),
    coalesce(round(100.0*count(*) filter (where t.status='no_show')/nullif(count(t.id),0),1),0),
    coalesce((select round(avg(s.score),2) from surveys s join tickets t2 on t2.id=s.ticket_id
      where t2.branch_id=b.id and t2.issued_at>now()-p_days*interval '1 day'),0)
  from branches b left join tickets t on t.branch_id=b.id and t.issued_at>now()-p_days*interval '1 day'
  where my_role() in ('manager','admin') group by b.id order by 6 desc $$;

-- mesin alert + eskalasi + expire tiket remote
create or replace function qf_tick() returns void language plpgsql security definer set search_path=public as $$
declare r alert_rules; v numeric;
begin
  for r in select * from alert_rules where active loop
    v := case r.metric
      when 'wait_over' then coalesce((select max(extract(epoch from now()-issued_at))/60 from tickets where branch_id=r.branch_id and status='waiting'),0)
      when 'queue_over' then (select count(*) from tickets where branch_id=r.branch_id and status='waiting')
      when 'idle_counter' then coalesce((select max(extract(epoch from now()-last_status_at))/60 from counters where branch_id=r.branch_id and status='available'),0)
      when 'no_show_rate' then coalesce((select 100.0*count(*) filter (where status='no_show')/nullif(count(*),0) from tickets where branch_id=r.branch_id and issued_at>now()-interval '1 hour'),0)
    end;
    if v>r.threshold then
      if not exists(select 1 from alerts where rule_id=r.id and status<>'resolved') then
        insert into alerts(rule_id,branch_id,message,severity)
        values(r.id,r.branch_id,r.metric||': '||round(v,1)||' (batas '||r.threshold||')',case when v>r.threshold*1.5 then 'critical' else 'warning' end);
      end if;
    else
      update alerts set status='resolved',resolved_at=now() where rule_id=r.id and status<>'resolved';
    end if;
  end loop;
  update alerts a set escalated=true,severity='critical' from alert_rules r
    where r.id=a.rule_id and a.status='open' and not a.escalated and a.created_at<now()-r.escalate_after_min*interval '1 minute';
  update tickets set status='expired',ended_at=now() where status='waiting' and expires_at is not null and expires_at<now();
end $$;
-- jadwalkan tiap 30 detik (aktifkan extension pg_cron dulu):
-- select cron.schedule('qf-tick','30 seconds','select public.qf_tick()');

-- layar antrian publik (hanya nomor, tanpa data pribadi)
create view display_board as
  select t.id,t.branch_id,t.service_id,t.counter_id,t.number,t.status,t.priority,t.recall_count,t.called_at,t.issued_at,c.name as counter_name
  from tickets t left join counters c on c.id=t.counter_id
  where t.status in ('waiting','called','serving') and t.issued_at>now()-interval '1 day';
grant select on display_board to anon,authenticated;

-- RLS
alter table branches enable row level security; alter table services enable row level security;
alter table counters enable row level security; alter table profiles enable row level security;
alter table tickets enable row level security; alter table queue_events enable row level security;
alter table alert_rules enable row level security; alter table alerts enable row level security;
alter table surveys enable row level security; alter table audit_log enable row level security;

create policy r1 on branches for select using (true);
create policy r2 on services for select using (true);
create policy r3 on counters for select using (true);
create policy w1 on branches for update using (is_staff(id) and my_role() in ('supervisor','manager','admin'));
create policy w2 on branches for insert with check (my_role()='admin');
create policy w3 on services for all using (my_role()='admin') with check (my_role()='admin');
create policy w4 on counters for all using (my_role()='admin') with check (my_role()='admin');
create policy p1 on profiles for select using (id=auth.uid() or my_role()='admin');
create policy p2 on profiles for update using (my_role()='admin');
create policy t1 on tickets for select using (true); -- nomor tiket publik (kontak ada di ticket_contacts yang terkunci)
create policy e1 on queue_events for select using (is_staff(branch_id));
create policy ar1 on alert_rules for all using (is_staff(branch_id) and my_role() in ('supervisor','manager','admin'))
  with check (is_staff(branch_id) and my_role() in ('supervisor','manager','admin'));
create policy al1 on alerts for select using (is_staff(branch_id));
create policy al2 on alerts for update using (is_staff(branch_id));
create policy s1 on surveys for insert with check
  (exists(select 1 from tickets where id=ticket_id and customer_id=auth.uid() and status='completed'));
create policy s2 on surveys for select using (my_role() in ('manager','admin'));
create policy au1 on audit_log for select using (my_role()='admin');

-- realtime
alter publication supabase_realtime add table tickets, counters, alerts, branches;

-- seed contoh
with b as (insert into branches(name,address) values('Cabang Yogyakarta','Jl. Malioboro 1') returning id),
s as (insert into services(branch_id,name,code,avg_service_sec)
  select id,x.n,x.c,x.a from b,(values('Customer Service','A',360),('Teller','B',180),('Informasi','C',120)) x(n,c,a) returning id),
c as (insert into counters(branch_id,name) select id,x from b,unnest(array['Loket 1','Loket 2','Loket 3']) x returning id)
insert into alert_rules(branch_id,metric,threshold) select id,m.k,m.v from b,(values('wait_over',15),('queue_over',30),('idle_counter',10),('no_show_rate',20)) m(k,v);

-- jadikan akun lain admin:
-- update profiles set role='admin' where id=(select id from auth.users where email='kamu@email.com');

-- ===================== TAMBAHAN: webhook, notifikasi, device, forecast =====================
alter table tickets add column notified bool default false;
create table webhooks(
  id uuid primary key default gen_random_uuid(), url text not null,
  secret text not null default encode(gen_random_bytes(16),'hex'), events text[] default '{}',
  active bool default true, created_at timestamptz default now());
create table outbox(
  id bigserial primary key, kind text check (kind in ('notify','webhook')), target text, channel text default 'whatsapp',
  payload jsonb, status text default 'pending', attempts int default 0, next_at timestamptz default now(),
  last_error text, created_at timestamptz default now());
create index on outbox(status,next_at);
create table devices(
  id uuid primary key default gen_random_uuid(), branch_id uuid references branches on delete cascade,
  name text not null, kind text check (kind in ('kiosk','display','printer')), last_seen timestamptz);
alter table webhooks enable row level security; alter table outbox enable row level security; alter table devices enable row level security;
create policy wh1 on webhooks for all using (my_role()='admin') with check (my_role()='admin');
create policy dv1 on devices for select using (is_staff(branch_id));
create policy dv2 on devices for all using (my_role()='admin') with check (my_role()='admin');
create trigger a5 after insert or update or delete on webhooks for each row execute function audit();

-- event -> outbox (webhook bertanda tangan + notifikasi saat dipanggil)
create or replace function enqueue_events() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into outbox(kind,target,payload)
    select 'webhook',w.id::text,jsonb_build_object('type',new.type,'ticket_id',new.ticket_id,'branch_id',new.branch_id,'at',new.created_at,'data',new.payload)
    from webhooks w where w.active and (cardinality(w.events)=0 or new.type=any(w.events));
  if new.type='ticket_called' then
    insert into outbox(kind,target,payload) select 'notify',k.phone,jsonb_build_object('text','Tiket '||t.number||' dipanggil. Silakan menuju loket.')
    from tickets t join ticket_contacts k on k.ticket_id=t.id where t.id=new.ticket_id;
  end if;
  return new;
end $$;
create trigger q_enqueue after insert on queue_events for each row execute function enqueue_events();

-- notifikasi "3 tiket lagi"
create or replace function qf_notify() returns void language plpgsql security definer set search_path=public as $$
begin
  with u as (
    update tickets t set notified=true where t.status='waiting' and exists(select 1 from ticket_contacts k where k.ticket_id=t.id) and not t.notified
      and (select count(*) from tickets x where x.branch_id=t.branch_id and x.service_id=t.service_id and x.status='waiting'
           and x.id<>t.id and (x.priority>t.priority or (x.priority=t.priority and x.issued_at<t.issued_at)))<=3
    returning t.number,(select k.phone from ticket_contacts k where k.ticket_id=t.id) as phone)
  insert into outbox(kind,target,payload) select 'notify',phone,jsonb_build_object('text','Giliran Anda hampir tiba. Tiket '||number) from u;
end $$;

-- heartbeat device + alert device offline
create or replace function heartbeat(p_device uuid) returns void language sql security definer set search_path=public as
$$ update devices set last_seen=now() where id=p_device $$;
create or replace function qf_devices() returns void language plpgsql security definer set search_path=public as $$
declare d devices;
begin
  for d in select * from devices loop
    if d.last_seen is null or d.last_seen<now()-interval '2 minutes' then
      if not exists(select 1 from alerts where message='Device offline: '||d.name and status<>'resolved') then
        insert into alerts(branch_id,message,severity) values(d.branch_id,'Device offline: '||d.name,'critical');
      end if;
    else
      update alerts set status='resolved',resolved_at=now() where message='Device offline: '||d.name and status<>'resolved';
    end if;
  end loop;
end $$;

create or replace function qf_tick_all() returns void language plpgsql as $$
begin perform qf_tick(); perform qf_notify(); perform qf_devices(); end $$;
-- jadwal (pg_cron + pg_net):
-- select cron.schedule('qf-all','30 seconds','select public.qf_tick_all()');
-- select cron.schedule('qf-dispatch','30 seconds',$$select net.http_post('https://PROJECT.supabase.co/functions/v1/dispatch',
--   headers:=jsonb_build_object('Authorization','Bearer SERVICE_ROLE_KEY'))$$);

-- forecast beban 8 jam ke depan (rata-rata hari+jam yang sama, 28 hari) + rekomendasi counter (utilisasi target 80%)
create or replace function forecast(p_branch uuid) returns table(hour_ts timestamptz,expected numeric,counters_needed int)
language sql stable security definer set search_path=public as $$
  with h as (select generate_series(date_trunc('hour',now()),date_trunc('hour',now())+interval '7 hours',interval '1 hour') ts),
  hist as (select extract(dow from issued_at at time zone 'Asia/Jakarta') d, extract(hour from issued_at at time zone 'Asia/Jakarta') hr,
           date_trunc('day',issued_at) dy, count(*) c from tickets where branch_id=p_branch and issued_at>now()-interval '28 days' group by 1,2,3),
  av as (select d,hr,avg(c) a from hist group by 1,2)
  select h.ts, round(coalesce(av.a,0),1),
    ceil(coalesce(av.a,0)*(select coalesce(avg(avg_service_sec),300) from services where branch_id=p_branch)/3600/0.8)::int
  from h left join av on av.d=extract(dow from h.ts at time zone 'Asia/Jakarta') and av.hr=extract(hour from h.ts at time zone 'Asia/Jakarta')
  where is_staff(p_branch) order by 1 $$;

-- Akun demo SIAntri (petugas loket + admin). GANTI password sebelum produksi.
do $$
declare r record; uid uuid; bid uuid := (select id from branches order by created_at limit 1);
begin
  for r in select * from (values('petugas@siantri.com','petugas123','agent'),('admin@siantri.com','admin123','admin')) v(mail,pass,rl) loop
    if exists(select 1 from auth.users where email=r.mail) then continue; end if;
    uid := gen_random_uuid();
    insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
      created_at,updated_at,confirmation_token,email_change,email_change_token_new,recovery_token)
    values('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',r.mail,crypt(r.pass,gen_salt('bf')),now(),
      '{"provider":"email","providers":["email"]}','{}',now(),now(),'','','','');
    insert into auth.identities(id,user_id,identity_data,provider,provider_id,last_sign_in_at,created_at,updated_at)
    values(gen_random_uuid(),uid,jsonb_build_object('sub',uid::text,'email',r.mail),'email',uid::text,now(),now(),now());
    update profiles set role=r.rl::user_role,branch_id=bid where id=uid;
  end loop;
end $$;
