-- 名簿で名前・よみを直したら、コンペの出欠にも反映する

-- 1) 今ずれている分を、名簿に合わせる（1回だけ）
update public.entries e
   set last_name = p.last_name, first_name = p.first_name,
       last_kana = p.last_kana, first_kana = p.first_kana, name = p.name
  from public.players p
 where e.player_id = p.id
   and (e.name is distinct from p.name or e.last_kana is distinct from p.last_kana or e.first_kana is distinct from p.first_kana);

-- 2) これからは、名簿を直すたびに自動で出欠にも反映する
create or replace function public.sync_player_names() returns trigger
language plpgsql security definer set search_path to 'public' as $$
begin
  if new.name is distinct from old.name or new.last_name is distinct from old.last_name or new.first_name is distinct from old.first_name
     or new.last_kana is distinct from old.last_kana or new.first_kana is distinct from old.first_kana then
    update public.entries
       set last_name = new.last_name, first_name = new.first_name,
           last_kana = new.last_kana, first_kana = new.first_kana, name = new.name
     where player_id = new.id;
  end if;
  return new;
end $$;

drop trigger if exists players_sync_names on public.players;
create trigger players_sync_names after update on public.players
  for each row execute function public.sync_player_names();
