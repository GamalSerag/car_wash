-- Run this entire file in Supabase SQL Editor after carpet_orders.sql.
-- Existing orders and older APKs default to one piece. Prices and payments
-- are unchanged. Existing orders can be edited to set their actual count.
begin;

alter table public.carpet_orders
add column if not exists piece_count integer not null default 1;

alter table public.carpet_orders
drop constraint if exists carpet_orders_piece_count_check;
alter table public.carpet_orders
add constraint carpet_orders_piece_count_check check (piece_count between 1 and 9999);

commit;
