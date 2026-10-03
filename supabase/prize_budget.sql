-- 商品の予算と、各賞の金額・数量
alter table public.events add column if not exists prize_budget integer check (prize_budget is null or prize_budget >= 0);
alter table public.awards add column if not exists price integer check (price is null or price >= 0);
alter table public.awards add column if not exists qty integer not null default 1 check (qty >= 1);
