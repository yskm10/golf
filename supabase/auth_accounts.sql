-- LINEログイン（Supabase Auth）とチームの紐づけ
-- チームの権限は従来どおり x-team-token で判定する。ログインは「トークンを取り戻す」ための層。
-- 幹事が複数いるチームのため、1チームに複数のアカウントを紐づけられる（team_members）。

create table if not exists public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
create index if not exists team_members_user_idx on public.team_members(user_id);

alter table public.team_members enable row level security;
-- ポリシーは作らない = 下のRPC以外からは、読み書きできない
revoke all on public.team_members from anon, authenticated;

-- 管理用トークンを知っているチームを、ログイン中のアカウントに紐づける
create or replace function public.claim_team(p_token text)
returns table(id uuid, name text, admin_token text)
language plpgsql security definer set search_path = public as $$
declare v_team public.teams;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into v_team from public.teams t where t.admin_token = p_token;
  if not found then return; end if;
  insert into public.team_members(team_id, user_id) values (v_team.id, auth.uid()) on conflict do nothing;
  return query select v_team.id, v_team.name, v_team.admin_token;
end $$;

-- ログイン中のアカウントに紐づいたチーム（管理用トークン付き）を返す
create or replace function public.my_teams()
returns table(id uuid, name text, admin_token text)
language sql security definer set search_path = public stable as $$
  select t.id, t.name, t.admin_token
  from public.teams t join public.team_members m on m.team_id = t.id
  where m.user_id = auth.uid()
  order by t.created_at;
$$;

revoke all on function public.claim_team(text) from public, anon;
revoke all on function public.my_teams() from public, anon;
grant execute on function public.claim_team(text) to authenticated;
grant execute on function public.my_teams() to authenticated;

-- チームとアカウントの紐づけを外す（「この端末から外す」で、次回ログイン時に復活させないため）
create or replace function public.unclaim_team(p_token text)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  delete from public.team_members m using public.teams t
   where t.admin_token = p_token and m.team_id = t.id and m.user_id = auth.uid();
end $$;
revoke all on function public.unclaim_team(text) from public, anon;
grant execute on function public.unclaim_team(text) to authenticated;
