-- ============================================================
--  MindWell — Supabase schema (Authentication phase)
--  Run this in: Supabase Dashboard → SQL Editor → New query → Run
-- ============================================================

-- ---------- profiles ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  reminder_time text,
  support_style text,
  created_at timestamp default now()
);

-- ---------- Onboarding / personalization columns ----------
-- These drive content PRIORITIZATION only. They never restrict access to any
-- feature — every resource, exercise and support category stays available.
-- Re-runnable: "add column if not exists" is a no-op on existing databases.
alter table public.profiles add column if not exists privacy_acknowledged boolean default false;
alter table public.profiles add column if not exists focus_areas jsonb default '[]'::jsonb;
alter table public.profiles add column if not exists support_styles jsonb default '[]'::jsonb;
alter table public.profiles add column if not exists checkin_frequency text;
alter table public.profiles add column if not exists checkin_time text;
alter table public.profiles add column if not exists onboarding_completed boolean default false;
alter table public.profiles add column if not exists reminders_enabled boolean default true;
-- Role gate for the separate admin dashboard. 'student' (default) | 'admin'.
alter table public.profiles add column if not exists role text default 'student';

-- ---------- Row Level Security ----------
alter table public.profiles enable row level security;

-- A user may only ever touch their OWN profile row (auth.uid() = id).
-- No policy grants access to other users' rows, so cross-user access is impossible.

drop policy if exists "Profiles are viewable by owner" on public.profiles;
create policy "Profiles are viewable by owner"
  on public.profiles for select
  using (auth.uid() = id);

drop policy if exists "Profiles can be inserted by owner" on public.profiles;
create policy "Profiles can be inserted by owner"
  on public.profiles for insert
  with check (auth.uid() = id);

drop policy if exists "Profiles can be updated by owner" on public.profiles;
create policy "Profiles can be updated by owner"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- ---------- Auto-create a profile row on signup ----------
-- This guarantees a profile exists even when email confirmation is on
-- (i.e. before the client has an authenticated session to insert with).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
--  Guided Conversational Journaling ("Let It Out")
--  Text AND (future) Vapi voice conversations share these tables.
-- ============================================================

-- ---------- conversations ----------
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz default now(),
  summary jsonb            -- { feeling, mainStressor, brightSpot }
);

-- ---------- messages ----------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender text not null check (sender in ('user', 'mindwell')),
  message text,
  created_at timestamptz default now()
);

create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at);
create index if not exists conversations_user_idx on public.conversations (user_id, created_at desc);

-- ---------- Row Level Security ----------
alter table public.conversations enable row level security;
alter table public.messages enable row level security;

-- conversations: a user may only touch their own conversations.
drop policy if exists "Conversations selectable by owner" on public.conversations;
create policy "Conversations selectable by owner" on public.conversations
  for select using (auth.uid() = user_id);
drop policy if exists "Conversations insertable by owner" on public.conversations;
create policy "Conversations insertable by owner" on public.conversations
  for insert with check (auth.uid() = user_id);
drop policy if exists "Conversations updatable by owner" on public.conversations;
create policy "Conversations updatable by owner" on public.conversations
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Conversations deletable by owner" on public.conversations;
create policy "Conversations deletable by owner" on public.conversations
  for delete using (auth.uid() = user_id);

-- messages: access is gated through the parent conversation's owner.
drop policy if exists "Messages selectable by owner" on public.messages;
create policy "Messages selectable by owner" on public.messages
  for select using (exists (
    select 1 from public.conversations c
    where c.id = conversation_id and c.user_id = auth.uid()
  ));
drop policy if exists "Messages insertable by owner" on public.messages;
create policy "Messages insertable by owner" on public.messages
  for insert with check (exists (
    select 1 from public.conversations c
    where c.id = conversation_id and c.user_id = auth.uid()
  ));
drop policy if exists "Messages deletable by owner" on public.messages;
create policy "Messages deletable by owner" on public.messages
  for delete using (exists (
    select 1 from public.conversations c
    where c.id = conversation_id and c.user_id = auth.uid()
  ));

-- ============================================================
--  Mood Memory — emotional timeline
--  Manual check-ins (source='manual') and conversation-suggested
--  moods (source='conversation') share this table.
-- ============================================================
create table if not exists public.mood_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  mood_score integer,
  mood_label text,
  note text,
  source text default 'manual',   -- 'manual' | 'conversation'
  created_at timestamp default now()
);

create index if not exists mood_logs_user_idx on public.mood_logs (user_id, created_at desc);

alter table public.mood_logs enable row level security;

-- A user may only ever touch their OWN mood logs.
drop policy if exists "Mood logs selectable by owner" on public.mood_logs;
create policy "Mood logs selectable by owner" on public.mood_logs
  for select using (auth.uid() = user_id);
drop policy if exists "Mood logs insertable by owner" on public.mood_logs;
create policy "Mood logs insertable by owner" on public.mood_logs
  for insert with check (auth.uid() = user_id);
drop policy if exists "Mood logs updatable by owner" on public.mood_logs;
create policy "Mood logs updatable by owner" on public.mood_logs
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Mood logs deletable by owner" on public.mood_logs;
create policy "Mood logs deletable by owner" on public.mood_logs
  for delete using (auth.uid() = user_id);

-- ============================================================
--  Personalized Wellness Reminder Engine
--  reminder_content = shared template library (read-only to users)
--  reminders        = each user's generated / delivered reminders
-- ============================================================

-- ---------- reminder_content (shared templates) ----------
create table if not exists public.reminder_content (
  id uuid primary key default gen_random_uuid(),
  category text,
  title text,
  body text
);

alter table public.reminder_content enable row level security;
-- Templates are non-sensitive and shared; any signed-in user may read them.
drop policy if exists "Reminder content readable" on public.reminder_content;
create policy "Reminder content readable" on public.reminder_content
  for select using (true);

-- Seed templates (only when the table is empty, so re-runs are safe).
insert into public.reminder_content (category, title, body)
select v.category, v.title, v.body from (values
  ('Stress Management', 'Take a small pause.', 'You''ve been working hard lately. Step away for a few minutes and breathe.'),
  ('Stress Management', 'A short break might help.', 'You''ve been carrying a lot academically. A short break might help.'),
  ('Stress Management', 'One thing at a time.', 'You don''t have to hold it all at once. Pick one small next step.'),
  ('Sleep & Rest', 'Prepare for rest.', 'A little rest today can make tomorrow easier.'),
  ('Sleep & Rest', 'Wind down a little earlier.', 'Try winding down a little earlier tonight — your mind will thank you.'),
  ('Sleep & Rest', 'Let the day soften.', 'Dim the screens and let your shoulders drop. Rest is allowed.'),
  ('Physical Wellbeing', 'A sip and a stretch.', 'A glass of water and a gentle stretch can lift the next hour.'),
  ('Physical Wellbeing', 'Move a little.', 'A short walk, even around the block, can help clear your head.'),
  ('Social Connection', 'Reach out.', 'A quick message to someone you trust can make a difference.'),
  ('Social Connection', 'You''re not alone.', 'Sharing a small part of your day with someone can lighten it.'),
  ('Motivation', 'Small steps count.', 'You don''t need a perfect day — just the next small step.'),
  ('Motivation', 'Proud of you.', 'Showing up today, even softly, is enough.'),
  ('Self-Care', 'Be gentle with yourself today.', 'Some days ask a lot of us. Treat yourself with the kindness you''d give a friend.'),
  ('Self-Care', 'Permission to rest.', 'You''re allowed to slow down and take care of you.')
) as v(category, title, body)
where not exists (select 1 from public.reminder_content);

-- ---------- reminders (per-user) ----------
create table if not exists public.reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  title text,
  body text,
  category text,
  scheduled_time timestamp,
  delivered_at timestamp,
  acknowledged boolean default false,
  created_at timestamp default now()
);

create index if not exists reminders_user_idx on public.reminders (user_id, created_at desc);

alter table public.reminders enable row level security;

drop policy if exists "Reminders selectable by owner" on public.reminders;
create policy "Reminders selectable by owner" on public.reminders
  for select using (auth.uid() = user_id);
drop policy if exists "Reminders insertable by owner" on public.reminders;
create policy "Reminders insertable by owner" on public.reminders
  for insert with check (auth.uid() = user_id);
drop policy if exists "Reminders updatable by owner" on public.reminders;
create policy "Reminders updatable by owner" on public.reminders
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
drop policy if exists "Reminders deletable by owner" on public.reminders;
create policy "Reminders deletable by owner" on public.reminders
  for delete using (auth.uid() = user_id);

-- ============================================================
--  Support alerts log (anonymized) — feeds aggregate admin stats only.
--  Stores user_id + timestamp; never any mood detail.
-- ============================================================
create table if not exists public.support_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade,
  created_at timestamp default now()
);
create index if not exists support_alerts_created_idx on public.support_alerts (created_at);
alter table public.support_alerts enable row level security;
drop policy if exists "Support alerts insertable by owner" on public.support_alerts;
create policy "Support alerts insertable by owner" on public.support_alerts
  for insert with check (auth.uid() = user_id);
drop policy if exists "Support alerts selectable by owner" on public.support_alerts;
create policy "Support alerts selectable by owner" on public.support_alerts
  for select using (auth.uid() = user_id);

-- ============================================================
--  ADMIN DASHBOARD — aggregate, anonymized statistics ONLY
--  Privacy-first: these SECURITY DEFINER functions compute aggregates
--  server-side and return ONLY counts/distributions — never names,
--  emails, reflections, conversations, moods, notes or reminders.
--  Every function refuses non-admin callers.
-- ============================================================

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- 1) Summary metrics (the eight cards).
create or replace function public.admin_metrics()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare result json;
begin
  if not public.is_admin() then raise exception 'forbidden: admin only'; end if;
  select json_build_object(
    'total_users',          (select count(*) from public.profiles),
    'total_reflections',    (select count(*) from public.conversations where summary is not null),
    'total_conversations',  (select count(*) from public.conversations),
    'total_mood_logs',      (select count(*) from public.mood_logs),
    'total_reminders',      (select count(*) from public.reminders),
    'total_support_alerts', (select count(*) from public.support_alerts),
    'most_common_mood',     (select mood_label from public.mood_logs
                              where mood_label is not null
                              group by mood_label order by count(*) desc limit 1),
    'avg_mood_score',       (select round(avg(mood_score)::numeric, 2) from public.mood_logs)
  ) into result;
  return result;
end;
$$;

-- 2) Mood distribution (pie). Always returns all five buckets.
create or replace function public.admin_mood_distribution()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare result json;
begin
  if not public.is_admin() then raise exception 'forbidden: admin only'; end if;
  select json_build_object(
    'Great',  count(*) filter (where mood_label = 'Great'),
    'Okay',   count(*) filter (where mood_label = 'Okay'),
    'Meh',    count(*) filter (where mood_label = 'Meh'),
    'Rough',  count(*) filter (where mood_label = 'Rough'),
    'Sleepy', count(*) filter (where mood_label = 'Sleepy')
  ) into result from public.mood_logs;
  return result;
end;
$$;

-- 3) Weekly mood check-ins (line) — counts per day for the last 7 days.
create or replace function public.admin_weekly_checkins()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare result json;
begin
  if not public.is_admin() then raise exception 'forbidden: admin only'; end if;
  select coalesce(json_agg(json_build_object(
           'label', to_char(d.day, 'Dy'),
           'date',  to_char(d.day, 'YYYY-MM-DD'),
           'count', coalesce(c.cnt, 0)
         ) order by d.day), '[]'::json)
  into result
  from (select generate_series(current_date - 6, current_date, interval '1 day')::date as day) d
  left join (
    select created_at::date as day, count(*) as cnt
    from public.mood_logs
    where created_at >= current_date - 6
    group by created_at::date
  ) c on c.day = d.day;
  return result;
end;
$$;

-- 4) Reminder engagement (bar): completed / dismissed / remind-later.
create or replace function public.admin_reminder_engagement()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare result json;
begin
  if not public.is_admin() then raise exception 'forbidden: admin only'; end if;
  select json_build_object(
    'completed',    count(*) filter (where acknowledged = true),
    'dismissed',    count(*) filter (where acknowledged = false and delivered_at is not null),
    'remind_later', count(*) filter (where scheduled_time > created_at + interval '30 minutes')
  ) into result from public.reminders;
  return result;
end;
$$;

-- 5) Recent activity feed — today's aggregate counts only.
create or replace function public.admin_recent_activity()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare result json;
begin
  if not public.is_admin() then raise exception 'forbidden: admin only'; end if;
  select json_build_object(
    'new_users_today',     (select count(*) from public.profiles      where created_at::date = current_date),
    'mood_checkins_today', (select count(*) from public.mood_logs     where created_at::date = current_date),
    'conversations_today', (select count(*) from public.conversations where created_at::date = current_date),
    'reminders_today',     (select count(*) from public.reminders     where created_at::date = current_date),
    'support_alerts_today',(select count(*) from public.support_alerts where created_at::date = current_date)
  ) into result;
  return result;
end;
$$;

grant execute on function public.is_admin()                  to authenticated;
grant execute on function public.admin_metrics()             to authenticated;
grant execute on function public.admin_mood_distribution()   to authenticated;
grant execute on function public.admin_weekly_checkins()     to authenticated;
grant execute on function public.admin_reminder_engagement() to authenticated;
grant execute on function public.admin_recent_activity()     to authenticated;

-- ============================================================
--  DEMO ADMIN ACCOUNT
--  1. Sign up admin@mindwell.com through the app (normal signup).
--  2. Run this file again (or just the statement below) to grant admin.
--  Safe to run before the account exists — it updates 0 rows.
-- ============================================================
update public.profiles p
set role = 'admin'
from auth.users u
where u.id = p.id
  and lower(u.email) = 'admin@mindwell.com';

-- ============================================================
--  Self-service account & data deletion (privacy-first)
--  A user may permanently delete ONLY their own account. Removing the
--  auth.users row cascades to profiles, conversations, messages,
--  mood_logs, reminders and support_alerts (all FK ... on delete cascade).
--  Explicit deletes are kept first for clarity/robustness.
-- ============================================================
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  delete from public.messages
    where conversation_id in (select id from public.conversations where user_id = uid);
  delete from public.conversations  where user_id = uid;
  delete from public.mood_logs      where user_id = uid;
  delete from public.reminders      where user_id = uid;
  delete from public.support_alerts where user_id = uid;
  delete from public.profiles       where id = uid;
  delete from auth.users            where id = uid;  -- cascades anything remaining
end;
$$;

grant execute on function public.delete_my_account() to authenticated;
