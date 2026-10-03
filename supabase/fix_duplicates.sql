-- 1) 二重に入っていた出欠（味波 隼人）を整理：組の配置を名簿につながった方へ移して、片方を消す
update public.group_members set entry_id = '0929e678-8f08-416f-962d-2675f049a9fc'
  where entry_id = 'bea4bf1f-2f1a-4285-ab75-af9a22348909';
delete from public.entries where id = 'bea4bf1f-2f1a-4285-ab75-af9a22348909';

-- 2) 出欠フォーム：名簿を作り直して名簿とのつながりが切れた同名の出欠があれば、その人につなぎ直す（二重登録を防ぐ）
create or replace function public.form_submit(p_form_token text, p_player_id uuid, p_last_name text, p_first_name text, p_last_kana text, p_first_kana text, p_attendance text, p_party text, p_avg_score integer, p_note text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  ev public.events;
  pl public.players;
  v_last text := regexp_replace(coalesce(p_last_name, ''), '[\s　]+', '', 'g');
  v_first text := regexp_replace(coalesce(p_first_name, ''), '[\s　]+', '', 'g');
  v_lk text := regexp_replace(coalesce(p_last_kana, ''), '[\s　]+', '', 'g');
  v_fk text := regexp_replace(coalesce(p_first_kana, ''), '[\s　]+', '', 'g');
  v_note text := nullif(left(trim(coalesce(p_note, '')), 500), '');
  v_party text := nullif(p_party, '');
  v_score int;
  eid uuid;
begin
  select * into ev from public.events where form_token = p_form_token;
  if not found then raise exception 'form_not_found'; end if;
  if not ev.form_open or (ev.form_deadline is not null and ev.form_deadline <= now()) then
    raise exception 'form_closed';
  end if;
  if p_attendance not in ('join', 'absent') then raise exception 'invalid_attendance'; end if;
  if v_party is not null and v_party not in ('join', 'absent') then raise exception 'invalid_party'; end if;
  if not ev.has_party then v_party := null; end if;

  -- 平均スコア：参加なら必須。0 は「不明」（初めての人）として保存しない
  if p_attendance = 'join' and p_avg_score is null then raise exception 'score_required'; end if;
  if p_avg_score is not null and p_avg_score <> 0 and p_avg_score not between 50 and 200 then
    raise exception 'invalid_score';
  end if;
  v_score := nullif(p_avg_score, 0);

  if p_player_id is not null then
    select * into pl from public.players where id = p_player_id and team_id = ev.team_id;
    if not found then raise exception 'player_not_found'; end if;
  else
    if length(v_last) = 0 or length(v_first) = 0 then raise exception 'name_required'; end if;
    if length(v_lk) = 0 or length(v_fk) = 0 then raise exception 'kana_required'; end if;
    v_last := left(v_last, 30);
    v_first := left(v_first, 30);
    v_lk := left(v_lk, 40);
    v_fk := left(v_fk, 40);
    select * into pl from public.players
      where team_id = ev.team_id
        and regexp_replace(lower(name), '[\s　]+', '', 'g') = lower(v_last || v_first)
      limit 1;
  end if;

  if pl.id is not null then
    -- 名簿とのつながりが切れた同名の出欠（名簿の作り直しなど）を、この人につなぎ直す
    update public.entries
       set player_id = pl.id, approval = 'approved'
     where event_id = ev.id and player_id is null
       and regexp_replace(lower(name), '[\s　]+', '', 'g') = regexp_replace(lower(pl.name), '[\s　]+', '', 'g')
       and not exists (select 1 from public.entries x where x.event_id = ev.id and x.player_id = pl.id);

    insert into public.entries as en
      (event_id, player_id, name, last_name, first_name, last_kana, first_kana,
       avg_score, attendance, party, note, approval, source, responded_at)
    values
      (ev.id, pl.id, pl.name, pl.last_name, pl.first_name, pl.last_kana, pl.first_kana,
       v_score, p_attendance, v_party, v_note, 'approved', 'form', now())
    on conflict (event_id, player_id) where player_id is not null
    do update set
      avg_score    = coalesce(excluded.avg_score, en.avg_score),
      attendance   = case when en.attendance = 'cancelled' then en.attendance else excluded.attendance end,
      party        = excluded.party,
      note         = excluded.note,
      responded_at = now()
    returning en.id into eid;
    return jsonb_build_object('ok', true, 'entry_id', eid, 'status', 'approved');
  end if;

  insert into public.entries as en
    (event_id, player_id, name, last_name, first_name, last_kana, first_kana,
     avg_score, attendance, party, note, approval, source, responded_at)
  values
    (ev.id, null, v_last || ' ' || v_first, v_last, v_first, v_lk, v_fk,
     v_score, p_attendance, v_party, v_note, 'pending', 'form', now())
  on conflict (event_id, lower(name)) where player_id is null
  do update set
    last_kana    = excluded.last_kana,
    first_kana   = excluded.first_kana,
    avg_score    = coalesce(excluded.avg_score, en.avg_score),
    attendance   = excluded.attendance,
    party        = excluded.party,
    note         = excluded.note,
    responded_at = now()
  returning en.id into eid;
  return jsonb_build_object('ok', true, 'entry_id', eid, 'status', 'pending');
end $function$;
