-- 出欠確認のLINE案内文を、幹事が編集して保存できるようにする（2026-11-25）
-- null のときは、コンペの内容から自動で作る。値があるときは、その文章を使う
alter table public.events add column if not exists line_text text;
