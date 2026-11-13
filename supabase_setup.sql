-- NOCTURNE / KZ Sleep Tracker: run in Supabase SQL Editor.
-- Creates user-owned sleep records and a private admin allow-list.

create table if not exists public.sleep_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  submitted_by_email text,
  sleep_date date not null,
  bedtime time not null,
  wake_time time not null,
  duration_minutes integer not null check (duration_minutes > 0 and duration_minutes <= 1200),
  source_device_id text not null,
  source_user_agent text,
  source_url text,
  created_at timestamptz not null default now()
);

alter table public.sleep_sessions add column if not exists submitted_by_email text;
create index if not exists sleep_sessions_user_date_idx on public.sleep_sessions (user_id, sleep_date desc);
create index if not exists sleep_sessions_created_at_idx on public.sleep_sessions (created_at desc);

create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.sleep_sessions enable row level security;
alter table public.admin_users enable row level security;
grant select, insert, delete on public.sleep_sessions to authenticated;
grant select on public.admin_users to authenticated;

drop policy if exists "Users and admins can read sleep sessions" on public.sleep_sessions;
create policy "Users and admins can read sleep sessions" on public.sleep_sessions
for select to authenticated
using (
  (select auth.uid()) = user_id
  or exists (select 1 from public.admin_users a where a.user_id = (select auth.uid()))
);

drop policy if exists "Users can insert their own sleep sessions" on public.sleep_sessions;
create policy "Users can insert their own sleep sessions" on public.sleep_sessions
for insert to authenticated
with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their own sleep sessions" on public.sleep_sessions;
create policy "Users can delete their own sleep sessions" on public.sleep_sessions
for delete to authenticated
using ((select auth.uid()) = user_id);

-- An admin can read only their own allow-list entry. No client-side role escalation.
drop policy if exists "Users can read their own admin role" on public.admin_users;
create policy "Users can read their own admin role" on public.admin_users
for select to authenticated
using ((select auth.uid()) = user_id);

-- Enable Realtime for new sleep submissions (safe to run repeatedly).
do $$
begin
  alter publication supabase_realtime add table public.sleep_sessions;
exception when duplicate_object then null;
when undefined_object then raise notice 'supabase_realtime publication not found; enable Realtime for sleep_sessions in the Supabase dashboard.';
end $$;

-- AFTER creating your own account, promote ONLY your account to admin:
-- 1. Supabase Dashboard > Authentication > Users
-- 2. Copy your account UUID (not KZ's UUID)
-- 3. Replace YOUR_ADMIN_USER_UUID below and run this separately:
-- insert into public.admin_users (user_id) values ('YOUR_ADMIN_USER_UUID') on conflict do nothing;
