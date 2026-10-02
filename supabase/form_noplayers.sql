-- 出欠フォームから名簿を渡さない（URLを知っている人にも名前一覧が見えないようにする）
create or replace function public.form_get(p_form_token text)
returns jsonb
language plpgsql
stable security definer
set search_path to 'public'
as $function$
declare ev public.events;
begin
  select * into ev from public.events where form_token = p_form_token;
  if not found then return null; end if;
  return jsonb_build_object(
    'event', jsonb_build_object(
      'name', ev.name,
      'event_date', ev.event_date,
      'course_name', ev.course_name,
      'has_party', ev.has_party,
      'form_deadline', ev.form_deadline,
      'is_open', ev.form_open and (ev.form_deadline is null or ev.form_deadline > now())
    ),
    'players', '[]'::jsonb
  );
end $function$;
