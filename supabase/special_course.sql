-- ニアピン・ドラコンを、OUTスタート組／INスタート組ごとに分けて記録できるようにする（空欄＝全体）
alter table public.special_records add column if not exists course text check (course in ('OUT', 'IN'));
