-- Glimmr update 2: child QR logins + work results
-- Run once in Supabase: SQL Editor -> New query -> paste -> Run

create table if not exists public.child_links (
  token text primary key,
  parent uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kid_id text not null,
  created_at timestamptz default now()
);
alter table public.child_links enable row level security;
create policy "own links" on public.child_links for all
  using (auth.uid() = parent) with check (auth.uid() = parent);

create table if not exists public.results (
  parent uuid not null default auth.uid() references auth.users(id) on delete cascade,
  kid text not null,
  day text not null,
  item text not null,
  result jsonb,
  at timestamptz default now(),
  primary key (parent, kid, day, item)
);
alter table public.results enable row level security;
create policy "own results" on public.results for all
  using (auth.uid() = parent) with check (auth.uid() = parent);

-- A child's device only knows its secret QR token. These two functions let it
-- read ONLY that child's timetable and save ONLY that child's results.
create or replace function public.child_get(t text) returns jsonb
language sql security definer set search_path = public as $$
  select jsonb_build_object(
    'kid', (select k from jsonb_array_elements(coalesce(p.data->'kids','[]'::jsonb)) k where k->>'id' = l.kid_id limit 1),
    'plan', coalesce((select jsonb_agg(a) from jsonb_array_elements(coalesce(p.data->'plan','[]'::jsonb)) a where a->>'kid' = l.kid_id), '[]'::jsonb),
    'results', coalesce((select jsonb_agg(jsonb_build_object('day', r.day, 'item', r.item, 'result', r.result))
                         from results r where r.parent = l.parent and r.kid = l.kid_id), '[]'::jsonb)
  )
  from child_links l join profiles p on p.id = l.parent
  where l.token = t;
$$;

create or replace function public.child_done(t text, d text, i text, res jsonb) returns boolean
language plpgsql security definer set search_path = public as $$
declare l child_links;
begin
  select * into l from child_links where token = t;
  if not found or length(d) > 10 or length(i) > 40 then return false; end if;
  insert into results(parent, kid, day, item, result) values (l.parent, l.kid_id, d, i, res)
  on conflict (parent, kid, day, item) do update set result = excluded.result, at = now();
  return true;
end $$;

revoke all on function public.child_get(text) from public;
revoke all on function public.child_done(text, text, text, jsonb) from public;
grant execute on function public.child_get(text) to anon, authenticated;
grant execute on function public.child_done(text, text, text, jsonb) to anon, authenticated;
