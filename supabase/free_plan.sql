-- 無料プランの上限（2026-11-11）
--  ・無料：チーム作成はログイン必須（1アカウントにつき、無料チームは1つまで）
--  ・無料：進行中のコンペは同時に1件まで（開催日が今日（日本時間）以降、または日付なし）
--  ・無料：AI読み取りは通算3回まで（読み取りに失敗した分は数えない。Edge Function側で判定）
--  ・有料（plan='pro'）：上記の制限なし。決済の仕組みができるまでは、SQLで plan を切り替える
-- ※ 上限の数字を変えるときは、このファイル、Edge Function（FREE_AI_LIMIT）、画面の文言の3か所を揃える

alter table public.teams add column if not exists plan text not null default 'free';
alter table public.teams drop constraint if exists teams_plan_check;
alter table public.teams add constraint teams_plan_check check (plan in ('free', 'pro'));
alter table public.teams add column if not exists created_by uuid references auth.users(id) on delete set null;

-- 既存のチーム（すべて開発者自身のもの）は、制限なしにしておく
update public.teams set plan = 'pro' where created_by is null and plan = 'free';

-- チーム作成：ログイン必須。作成者を記録し、そのままメンバーにする
create or replace function public.create_team(p_name text)
returns table(id uuid, admin_token text)
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_n int;
  v_id uuid;
  v_tok text;
begin
  if v_uid is null then raise exception 'login_required'; end if;
  if p_name is null or length(trim(p_name)) = 0 then raise exception 'name_required'; end if;
  select count(*) into v_n from public.teams t where t.created_by = v_uid and t.plan = 'free';
  if v_n >= 1 then raise exception 'free_team_limit'; end if;
  insert into public.teams (name, created_by) values (left(trim(p_name), 60), v_uid)
    returning teams.id, teams.admin_token into v_id, v_tok;
  insert into public.team_members (team_id, user_id) values (v_id, v_uid);
  return query select v_id, v_tok;
end $$;
revoke all on function public.create_team(text) from public, anon;
grant execute on function public.create_team(text) to authenticated;

-- 進行中のコンペは、無料プランでは同時に1件まで
create or replace function public.enforce_event_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_plan text;
  v_n int;
  v_today date := (now() at time zone 'Asia/Tokyo')::date;
begin
  select t.plan into v_plan from public.teams t where t.id = new.team_id;
  if coalesce(v_plan, 'free') = 'free' and (new.event_date is null or new.event_date >= v_today) then
    select count(*) into v_n from public.events e
     where e.team_id = new.team_id and (e.event_date is null or e.event_date >= v_today);
    if v_n >= 1 then raise exception 'free_event_limit'; end if;
  end if;
  return new;
end $$;
drop trigger if exists events_free_limit on public.events;
create trigger events_free_limit before insert on public.events
  for each row execute function public.enforce_event_limit();

-- 画面に出す、今のチームの状況（幹事用トークンで判定）
create or replace function public.team_status()
returns table(plan text, ai_used int, ai_limit int, events_active int, events_limit int)
language sql stable security definer set search_path = public as $$
  select t.plan,
    (select count(*)::int from public.read_log r where r.team_id = t.id and r.input_tokens is not null),
    3,
    (select count(*)::int from public.events e
      where e.team_id = t.id and (e.event_date is null or e.event_date >= (now() at time zone 'Asia/Tokyo')::date)),
    1
  from public.teams t where t.id = public.current_team_id();
$$;
grant execute on function public.team_status() to anon, authenticated;

-- 【現在の運用（2026-11-11〜）】公開前の友人テスト中は、すべて有料扱い（制限なし）にしている。
--   alter table public.teams alter column plan set default 'pro';
--   公開するときは、次の2行で、無料プランの初期値に戻す（既存チームを free に戻すかは、そのとき決める）。
--   alter table public.teams alter column plan set default 'free';

