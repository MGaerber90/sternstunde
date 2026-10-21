-- =====================================================================
-- Sternstunde: Datenbank für Supabase
--
-- Enthält KEINE personenbezogenen Daten. Schüler, PINs, Klassencode und
-- Lehrer-PIN kommen aus seed.local.sql (wird nicht hochgeladen).
--
-- Ausführen: Supabase-Dashboard > SQL Editor > New query > Inhalt
-- einfügen > Run. Danach genauso mit seed.local.sql.
-- Die Datei kann gefahrlos mehrfach ausgeführt werden.
-- Hinweis: Supabase verbietet DELETE ohne WHERE (pg_safeupdate), daher 'where true'.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Tabellen
-- ---------------------------------------------------------------------
create table if not exists app_meta (
  id int primary key default 1 check (id = 1),
  class_code text not null,
  teacher_pin_hash text not null,
  settings jsonb not null default '{}'::jsonb,
  goal jsonb,
  goal_history jsonb not null default '[]'::jsonb,
  version int not null default 0,
  sync bigint not null default 0
);

create table if not exists students (
  id text primary key,
  name text not null,
  pin text not null check (pin ~ '^\d{4}$'),
  sort int not null default 0,
  data jsonb not null default '{}'::jsonb,
  version int not null default 0
);

create table if not exists events (
  id text primary key,
  data jsonb not null
);

-- Bewusst ohne Spalte für den Absender: Feedback ist anonym.
create table if not exists feedback (
  id text primary key,
  ts bigint not null,
  cat text not null,
  text text not null
);

create table if not exists sessions (
  token uuid primary key default gen_random_uuid(),
  role text not null check (role in ('teacher', 'student')),
  student_id text,
  created timestamptz not null default now()
);

create table if not exists login_fails (
  key text primary key,
  fails int not null default 0,
  until timestamptz
);

-- Preise der Shop-Items, damit der Server Käufe prüfen kann.
create table if not exists item_prices (
  id text primary key,
  price int not null,
  ach text
);

-- Direkter Zugriff auf alle Tabellen ist gesperrt (RLS ohne Policies).
-- Alles läuft über die Funktionen unten, die jede Anfrage prüfen.
alter table app_meta enable row level security;
alter table students enable row level security;
alter table events enable row level security;
alter table feedback enable row level security;
alter table sessions enable row level security;
alter table login_fails enable row level security;
alter table item_prices enable row level security;

-- ---------------------------------------------------------------------
-- Hilfsfunktionen (nicht von außen aufrufbar)
-- ---------------------------------------------------------------------
create or replace function _now_ms() returns bigint
language sql stable set search_path = public, extensions as $$
  select (extract(epoch from clock_timestamp()) * 1000)::bigint
$$;

create or replace function _session(p_token uuid, p_role text default null) returns sessions
language plpgsql security definer set search_path = public, extensions as $$
declare s sessions;
begin
  select * into s from sessions where token = p_token and created > now() - interval '14 days';
  if not found then raise exception 'auth'; end if;
  if p_role is not null and s.role <> p_role then raise exception 'auth'; end if;
  return s;
end $$;

create or replace function _bump() returns bigint
language sql security definer set search_path = public, extensions as $$
  update app_meta set sync = sync + 1 where id = 1 returning sync
$$;

create or replace function _register_fail(p_key text, p_max int, p_lock interval) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into login_fails(key, fails) values (p_key, 1)
  on conflict (key) do update set fails = login_fails.fails + 1;
  update login_fails set until = now() + p_lock, fails = 0 where key = p_key and fails >= p_max;
end $$;

create or replace function _wait(p_key text) returns int
language sql security definer set search_path = public, extensions as $$
  select coalesce((select ceil(extract(epoch from (until - now())))::int from login_fails where key = p_key and until > now()), 0)
$$;

create or replace function _insert_feedback(p_cat text, p_text text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_cat is null or p_cat not in ('unklar', 'gut', 'idee', 'sonstiges') then raise exception 'invalid'; end if;
  if p_text is null or length(trim(p_text)) < 3 or length(p_text) > 300 then raise exception 'invalid'; end if;
  if (select count(*) from feedback where ts > _now_ms() - 300000) >= 40 then raise exception 'spam'; end if;
  insert into feedback(id, ts, cat, text) values (gen_random_uuid()::text, _now_ms(), p_cat, trim(p_text));
end $$;

-- ---------------------------------------------------------------------
-- Anmeldung
-- ---------------------------------------------------------------------
create or replace function list_students(p_code text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare m app_meta;
begin
  select * into m from app_meta where id = 1;
  if not found or upper(trim(coalesce(p_code, ''))) <> m.class_code then
    return jsonb_build_object('error', 'code');
  end if;
  return jsonb_build_object(
    'className', m.settings->>'className',
    'schoolYear', m.settings->>'schoolYear',
    'students', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'avatar', data->'avatar') order by sort, name) from students), '[]'::jsonb));
end $$;

create or replace function login_student(p_code text, p_id text, p_pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare m app_meta; w int; tok uuid;
begin
  select * into m from app_meta where id = 1;
  if not found or upper(trim(coalesce(p_code, ''))) <> m.class_code then return jsonb_build_object('error', 'code'); end if;
  w := _wait('s:' || p_id);
  if w > 0 then return jsonb_build_object('error', 'locked', 'wait', w); end if;
  if not exists (select 1 from students where id = p_id and pin = p_pin) then
    perform _register_fail('s:' || p_id, 5, interval '2 minutes');
    return jsonb_build_object('error', 'pin');
  end if;
  delete from login_fails where key = 's:' || p_id;
  delete from sessions where created < now() - interval '14 days';
  insert into sessions(role, student_id) values ('student', p_id) returning token into tok;
  return jsonb_build_object('token', tok);
end $$;

create or replace function login_teacher(p_pin text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare m app_meta; w int; tok uuid;
begin
  select * into m from app_meta where id = 1;
  if not found then return jsonb_build_object('error', 'setup'); end if;
  w := _wait('t');
  if w > 0 then return jsonb_build_object('error', 'locked', 'wait', w); end if;
  if m.teacher_pin_hash <> crypt(coalesce(p_pin, ''), m.teacher_pin_hash) then
    perform _register_fail('t', 5, interval '10 minutes');
    return jsonb_build_object('error', 'pin');
  end if;
  delete from login_fails where key = 't';
  insert into sessions(role) values ('teacher') returning token into tok;
  return jsonb_build_object('token', tok);
end $$;

create or replace function logout(p_token uuid) returns void
language sql security definer set search_path = public, extensions as $$
  delete from sessions where token = p_token
$$;

-- ---------------------------------------------------------------------
-- Lesen
-- ---------------------------------------------------------------------
create or replace function sync_version(p_token uuid) returns bigint
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _session(p_token);
  return (select sync from app_meta where id = 1);
end $$;

create or replace function get_state(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sessions; m app_meta; sid text; g jsonb;
begin
  s := _session(p_token);
  select * into m from app_meta where id = 1;
  if s.role = 'teacher' then
    return jsonb_build_object(
      'role', 'teacher',
      'sync', m.sync,
      'meta', jsonb_build_object('settings', m.settings, 'goal', m.goal, 'goalHistory', m.goal_history, 'version', m.version, 'classCode', m.class_code),
      'students', coalesce((select jsonb_agg(data || jsonb_build_object('id', id, 'name', name, 'pin', pin, '_v', version) order by sort, name) from students), '[]'::jsonb),
      'events', coalesce((select jsonb_agg(data) from events), '[]'::jsonb),
      'feedback', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'ts', ts, 'cat', cat, 'text', text) order by ts) from feedback), '[]'::jsonb));
  end if;

  -- Schüler: eigene Daten vollständig, von den anderen nur Name, Avatar, Geburtstag
  sid := s.student_id;
  g := m.goal;
  if jsonb_typeof(g) = 'object' then
    g := g || jsonb_build_object('contrib', jsonb_build_object(sid, coalesce(g->'contrib'->sid, '0'::jsonb)));
  end if;
  return jsonb_build_object(
    'role', 'student',
    'me', sid,
    'sync', m.sync,
    'meta', jsonb_build_object(
      'settings', jsonb_build_object('className', m.settings->'className', 'schoolYear', m.settings->'schoolYear', 'teacherLabel', m.settings->'teacherLabel'),
      'goal', g,
      'goalHistory', coalesce((select jsonb_agg((h - 'contributors') || jsonb_build_object('contributors', case when coalesce(h->'contributors', '[]'::jsonb) ? sid then jsonb_build_array(sid) else '[]'::jsonb end)) from jsonb_array_elements(m.goal_history) h), '[]'::jsonb),
      'version', m.version),
    'students', coalesce((select jsonb_agg(case when id = sid
        then data || jsonb_build_object('id', id, 'name', name, '_v', version)
        else jsonb_build_object('id', id, 'name', name, 'avatar', data->'avatar', 'birthday', data->'birthday', 'setupDone', data->'setupDone', 'stub', true) end
      order by sort, name) from students), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(data) from events), '[]'::jsonb),
    'feedback', '[]'::jsonb);
end $$;

-- ---------------------------------------------------------------------
-- Schreiben: Lehrkraft (alles in einer Transaktion, Versionsprüfung)
-- ---------------------------------------------------------------------
create or replace function teacher_apply(p_token uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare x jsonb; v_id text; newv int; res jsonb := '{}'::jsonb; vs jsonb := '{}'::jsonb; mg jsonb;
begin
  perform _session(p_token, 'teacher');

  for x in select * from jsonb_array_elements(coalesce(p->'students', '[]'::jsonb)) loop
    v_id := x->>'id';
    if v_id is null or coalesce(trim(x->>'name'), '') = '' or coalesce(x->>'pin', '') !~ '^\d{4}$' then raise exception 'invalid'; end if;
    if exists (select 1 from students where id = v_id) then
      update students set name = trim(x->>'name'), pin = x->>'pin', sort = coalesce((x->>'_sort')::int, sort),
        data = x - 'id' - 'name' - 'pin' - '_v' - '_sort' - 'stub', version = version + 1
      where id = v_id and version = coalesce((x->>'_v')::int, -1)
      returning version into newv;
      if not found then raise exception 'conflict'; end if;
    else
      insert into students(id, name, pin, sort, data)
      values (v_id, trim(x->>'name'), x->>'pin', coalesce((x->>'_sort')::int, 0), x - 'id' - 'name' - 'pin' - '_v' - '_sort' - 'stub')
      returning version into newv;
    end if;
    vs := vs || jsonb_build_object(v_id, newv);
  end loop;
  res := res || jsonb_build_object('students', vs);

  delete from sessions where student_id in (select jsonb_array_elements_text(coalesce(p->'deleteStudents', '[]'::jsonb)));
  delete from students where id in (select jsonb_array_elements_text(coalesce(p->'deleteStudents', '[]'::jsonb)));

  for x in select * from jsonb_array_elements(coalesce(p->'events', '[]'::jsonb)) loop
    if x->>'id' is null then raise exception 'invalid'; end if;
    insert into events(id, data) values (x->>'id', x) on conflict (id) do update set data = excluded.data;
  end loop;
  delete from events where id in (select jsonb_array_elements_text(coalesce(p->'deleteEvents', '[]'::jsonb)));

  if coalesce((p->>'clearFeedback')::boolean, false) then delete from feedback where true; end if;
  delete from feedback where id in (select jsonb_array_elements_text(coalesce(p->'deleteFeedback', '[]'::jsonb)));
  for x in select * from jsonb_array_elements(coalesce(p->'addFeedback', '[]'::jsonb)) loop
    perform _insert_feedback(x->>'cat', x->>'text');
  end loop;

  if jsonb_typeof(p->'meta') = 'object' then
    mg := p->'meta'->'goal';
    update app_meta set
      settings = coalesce(p->'meta'->'settings', settings) - 'teacherPin',
      goal = case when jsonb_typeof(mg) = 'object' then mg else null end,
      goal_history = coalesce(p->'meta'->'goalHistory', '[]'::jsonb),
      version = version + 1
    where id = 1 and version = coalesce((p->'meta'->>'_v')::int, -1)
    returning version into newv;
    if not found then raise exception 'conflict'; end if;
    res := res || jsonb_build_object('meta', newv);
  end if;

  return res || jsonb_build_object('sync', _bump());
end $$;

create or replace function teacher_set_pin(p_token uuid, p_new text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
begin
  perform _session(p_token, 'teacher');
  if coalesce(p_new, '') !~ '^\d{6,12}$' then raise exception 'invalid'; end if;
  update app_meta set teacher_pin_hash = crypt(p_new, gen_salt('bf')) where id = 1;
  return jsonb_build_object('ok', true);
end $$;

create or replace function teacher_import(p_token uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare x jsonb; i int := 0;
begin
  perform _session(p_token, 'teacher');
  if jsonb_typeof(p->'students') <> 'array' then raise exception 'invalid'; end if;
  delete from sessions where role = 'student';
  delete from students where true;
  for x in select * from jsonb_array_elements(p->'students') loop
    if coalesce(x->>'pin', '') !~ '^\d{4}$' then
      x := x || jsonb_build_object('pin', lpad((floor(random() * 10000))::int::text, 4, '0'));
    end if;
    insert into students(id, name, pin, sort, data)
    values (coalesce(x->>'id', gen_random_uuid()::text), trim(x->>'name'), x->>'pin', i, x - 'id' - 'name' - 'pin' - '_v' - '_sort' - 'stub');
    i := i + 1;
  end loop;
  delete from events where true;
  for x in select * from jsonb_array_elements(coalesce(p->'events', '[]'::jsonb)) loop
    insert into events(id, data) values (coalesce(x->>'id', gen_random_uuid()::text), x);
  end loop;
  delete from feedback where true;
  for x in select * from jsonb_array_elements(coalesce(p->'feedback', '[]'::jsonb)) loop
    insert into feedback(id, ts, cat, text) values (coalesce(x->>'id', gen_random_uuid()::text), coalesce((x->>'ts')::bigint, _now_ms()), coalesce(x->>'cat', 'sonstiges'), coalesce(x->>'text', ''));
  end loop;
  update app_meta set
    settings = coalesce(p->'settings', settings) - 'teacherPin',
    goal = case when jsonb_typeof(p->'goal') = 'object' then p->'goal' else null end,
    goal_history = coalesce(p->'goalHistory', '[]'::jsonb),
    version = version + 1
  where id = 1;
  return jsonb_build_object('ok', true, 'sync', _bump());
end $$;

-- ---------------------------------------------------------------------
-- Schreiben: Schüler (nur eigene Daten, nur erlaubte Felder)
-- ---------------------------------------------------------------------
create or replace function student_apply(p_token uuid, p jsonb) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sessions; cur students; o jsonb; n jsonb; added text[]; cost int; cnt int; x jsonb; newv int; res jsonb := '{}'::jsonb;
begin
  s := _session(p_token, 'student');

  if jsonb_typeof(p->'self') = 'object' then
    n := p->'self';
    select * into cur from students where id = s.student_id for update;
    if not found then raise exception 'auth'; end if;
    if cur.version <> coalesce((n->>'_v')::int, -1) then raise exception 'conflict'; end if;
    o := cur.data;

    -- Gekauftes kann nicht verschwinden, neue Items müssen bezahlt sein
    if exists (select 1 from jsonb_array_elements_text(coalesce(o->'owned', '[]'::jsonb)) e where not (coalesce(n->'owned', '[]'::jsonb) ? e)) then
      raise exception 'invalid';
    end if;
    select array_agg(distinct e) into added from jsonb_array_elements_text(coalesce(n->'owned', '[]'::jsonb)) e
      where not (coalesce(o->'owned', '[]'::jsonb) ? e);
    cost := 0;
    if added is not null then
      select count(*), coalesce(sum(price), 0) into cnt, cost from item_prices where id = any(added) and ach is null and price > 0;
      if cnt <> array_length(added, 1) then raise exception 'invalid'; end if;
    end if;
    if coalesce((o->>'stars')::int, 0) - coalesce((n->>'stars')::int, 0) <> cost then raise exception 'invalid'; end if;

    o := o || jsonb_build_object(
      'avatar', coalesce(n->'avatar', o->'avatar'),
      'setupDone', coalesce(n->'setupDone', o->'setupDone', 'false'::jsonb),
      'nick', to_jsonb(left(trim(coalesce(n->>'nick', '')), 20)),
      'nickAsked', coalesce(n->'nickAsked', 'false'::jsonb),
      'birthday', case when coalesce(n->>'birthday', '') ~ '^\d{2}-\d{2}$' then n->'birthday' else 'null'::jsonb end,
      'bdayAsked', coalesce(n->'bdayAsked', 'false'::jsonb),
      'help', case when jsonb_typeof(n->'help') = 'object' then jsonb_build_object('ts', _now_ms()) else 'null'::jsonb end,
      'helpCount', to_jsonb(greatest(coalesce((o->>'helpCount')::int, 0), coalesce((n->>'helpCount')::int, 0))),
      'loginDays', coalesce(n->'loginDays', o->'loginDays', '[]'::jsonb),
      'flags', coalesce(o->'flags', '{}'::jsonb) || coalesce(n->'flags', '{}'::jsonb),
      'joined', coalesce(o->'joined', n->'joined'),
      'achievements', coalesce(o->'achievements', '{}'::jsonb) || coalesce(n->'achievements', '{}'::jsonb),
      'owned', coalesce(n->'owned', '[]'::jsonb),
      'stars', to_jsonb(coalesce((n->>'stars')::int, 0)));
    -- Ein bereits laufender Hilferuf behält seine Startzeit
    if jsonb_typeof(o->'help') = 'object' and jsonb_typeof(cur.data->'help') = 'object' then
      o := o || jsonb_build_object('help', cur.data->'help');
    end if;

    update students set data = o, version = version + 1 where id = s.student_id returning version into newv;
    res := res || jsonb_build_object('self', newv);
  end if;

  for x in select * from jsonb_array_elements(coalesce(p->'feedback', '[]'::jsonb)) loop
    perform _insert_feedback(x->>'cat', x->>'text');
  end loop;

  return res || jsonb_build_object('sync', _bump());
end $$;

create or replace function donate(p_token uuid, p_n int) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare s sessions; cur students; m app_meta; g jsonb; sid text; ms bigint := _now_ms(); newp int;
begin
  s := _session(p_token, 'student');
  sid := s.student_id;
  if p_n is null or p_n < 1 or p_n > 50 then raise exception 'invalid'; end if;
  select * into m from app_meta where id = 1 for update;
  g := m.goal;
  if jsonb_typeof(g) is distinct from 'object' or (g->>'wonAt') is not null
     or (g->>'deadline')::date < (now() at time zone 'Europe/Berlin')::date then
    raise exception 'nomission';
  end if;
  select * into cur from students where id = sid for update;
  if coalesce((cur.data->>'stars')::int, 0) < p_n then raise exception 'stars'; end if;

  update students set version = version + 1, data = data || jsonb_build_object(
    'stars', coalesce((data->>'stars')::int, 0) - p_n,
    'donatedTotal', coalesce((data->>'donatedTotal')::int, 0) + p_n,
    'starLog', jsonb_build_array(jsonb_build_object('ts', ms, 'amount', -p_n, 'reason', 'Für die Mission gespendet')) || coalesce(data->'starLog', '[]'::jsonb))
  where id = sid;

  newp := coalesce((g->>'progress')::int, 0) + p_n;
  g := g || jsonb_build_object(
    'progress', newp,
    'donated', coalesce((g->>'donated')::int, 0) + p_n,
    'contrib', coalesce(g->'contrib', '{}'::jsonb) || jsonb_build_object(sid, coalesce((g->'contrib'->>sid)::int, 0) + p_n));
  if newp >= (g->>'target')::int then g := g || jsonb_build_object('wonAt', ms); end if;
  update app_meta set goal = g, version = version + 1 where id = 1;
  return jsonb_build_object('ok', true, 'sync', _bump());
end $$;

-- ---------------------------------------------------------------------
-- Rechte: von außen nur die öffentlichen Funktionen
-- ---------------------------------------------------------------------
revoke all on all tables in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function
  list_students(text), login_student(text, text, text), login_teacher(text), logout(uuid),
  sync_version(uuid), get_state(uuid), teacher_apply(uuid, jsonb), teacher_set_pin(uuid, text),
  teacher_import(uuid, jsonb), student_apply(uuid, jsonb), donate(uuid, int)
to anon, authenticated;
