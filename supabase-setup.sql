-- Run once in Supabase: SQL Editor -> New query -> paste -> Run
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now()
);

alter table public.profiles enable row level security;

-- Each parent can only see and change their own data
create policy "read own" on public.profiles for select using (auth.uid() = id);
create policy "insert own" on public.profiles for insert with check (auth.uid() = id);
create policy "update own" on public.profiles for update using (auth.uid() = id);
