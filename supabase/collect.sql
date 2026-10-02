-- 集金チェックリスト：参加者ごとの受取状況
alter table public.entries add column if not exists paid_amount integer check (paid_amount is null or paid_amount >= 0);
alter table public.entries add column if not exists paid_at timestamptz;
