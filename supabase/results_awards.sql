-- 成績（グロス・ネット・順位・性別）と、賞・商品
alter table public.entries add column if not exists gross integer check (gross is null or gross > 0);
alter table public.entries add column if not exists net numeric(5,1);
alter table public.entries add column if not exists result_rank integer check (result_rank is null or result_rank > 0);
alter table public.entries add column if not exists sex text check (sex is null or sex in ('M', 'F'));

create table if not exists public.awards (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  sort integer not null default 0,
  name text not null,
  rule text not null check (rule in ('net_rank', 'gross_rank', 'booby', 'special', 'manual')),
  rank_no integer check (rank_no is null or rank_no > 0),
  sex text check (sex is null or sex in ('M', 'F')),
  special_id uuid references public.special_records(id) on delete set null,
  prize text,
  winner_entry_id uuid references public.entries(id) on delete set null,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists awards_event on public.awards (event_id);

alter table public.awards enable row level security;
drop policy if exists awards_all on public.awards;
create policy awards_all on public.awards for all
  using (exists (select 1 from public.events e where e.id = awards.event_id and e.team_id = public.current_team_id()))
  with check (exists (select 1 from public.events e where e.id = awards.event_id and e.team_id = public.current_team_id()));
grant select, insert, update, delete on public.awards to anon, authenticated, service_role;
