-- 同じ組／別の組のルール（コンペごと・参加者ごと）
create table if not exists public.group_rules (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  kind text not null check (kind in ('together', 'apart')),
  entry_a uuid not null references public.entries(id) on delete cascade,
  entry_b uuid not null references public.entries(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (entry_a <> entry_b)
);
create unique index if not exists group_rules_uniq
  on public.group_rules (event_id, kind, least(entry_a, entry_b), greatest(entry_a, entry_b));
create index if not exists group_rules_event on public.group_rules (event_id);

alter table public.group_rules enable row level security;
drop policy if exists group_rules_all on public.group_rules;
create policy group_rules_all on public.group_rules for all
  using (exists (select 1 from public.events e where e.id = group_rules.event_id and e.team_id = public.current_team_id()))
  with check (exists (select 1 from public.events e where e.id = group_rules.event_id and e.team_id = public.current_team_id()));

grant select, insert, update, delete on public.group_rules to anon, authenticated, service_role;
