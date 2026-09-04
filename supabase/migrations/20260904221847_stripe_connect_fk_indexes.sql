-- Cover foreign keys used by marketplace settlement and creator reporting.

create index if not exists app_payments_purchase_idx
  on public.app_payments (purchase_id);

create index if not exists app_purchases_booking_slot_idx
  on public.app_purchases (booking_slot_id) where booking_slot_id is not null;
create index if not exists app_purchases_connected_account_idx
  on public.app_purchases (connected_account_id) where connected_account_id is not null;
create index if not exists app_purchases_post_idx
  on public.app_purchases (post_id);
create index if not exists app_purchases_price_idx
  on public.app_purchases (price_id);

create index if not exists app_creator_earnings_buyer_idx
  on public.app_creator_earnings (buyer_id, created_at desc);
create index if not exists app_creator_earnings_connected_account_idx
  on public.app_creator_earnings (connected_account_id);
create index if not exists app_creator_earnings_payment_idx
  on public.app_creator_earnings (payment_id) where payment_id is not null;
create index if not exists app_creator_earnings_post_idx
  on public.app_creator_earnings (post_id, created_at desc);
create index if not exists app_creator_earnings_purchasable_idx
  on public.app_creator_earnings (purchasable_id, created_at desc);

create index if not exists app_platform_fees_payment_idx
  on public.app_platform_fees (payment_id) where payment_id is not null;

create index if not exists app_refunds_creator_idx
  on public.app_refunds (creator_id, created_at desc);
create index if not exists app_refunds_buyer_idx
  on public.app_refunds (buyer_id, created_at desc);

create index if not exists app_payouts_connected_account_idx
  on public.app_payouts (connected_account_id, created_at desc);

create index if not exists app_payment_disputes_purchase_idx
  on public.app_payment_disputes (purchase_id) where purchase_id is not null;
create index if not exists app_payment_disputes_creator_idx
  on public.app_payment_disputes (creator_id, created_at desc) where creator_id is not null;
