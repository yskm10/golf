-- 同スコアのときの順位の決め方（コンペごとの優先順位）／生まれ年／後半9ホールのスコア
alter table public.events
  add column if not exists tiebreak_net text not null default 'gross,sex,age,countback',
  add column if not exists tiebreak_gross text not null default 'sex,age,countback',
  add column if not exists tb_sex text not null default 'F' check (tb_sex in ('F','M')),
  add column if not exists tb_age text not null default 'old' check (tb_age in ('old','young'));
alter table public.entries
  add column if not exists birth_year integer check (birth_year is null or birth_year between 1900 and 2100),
  add column if not exists score_in integer check (score_in is null or score_in between 20 and 150);
alter table public.players
  add column if not exists birth_year integer check (birth_year is null or birth_year between 1900 and 2100);
