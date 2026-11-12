create table public.app_businesses (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id),
  name text not null check (length(name) between 1 and 80),
  category text not null check (category in ('coffee_bakery','street_food')),
  pickup_address text not null check (length(pickup_address) between 1 and 240),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  location_updated_at timestamptz not null default now(),
  hours text not null default '',
  avatar_url text,
  photos text[] not null default '{}',
  paused boolean not null default true,
  published boolean not null default false,
  tax_bps integer check (tax_bps between 0 and 10000)
);
comment on column public.app_businesses.tax_bps is 'Configured by operations after tax review. NULL prevents checkout.';
create table public.app_business_products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.app_businesses(id),
  name text not null check (length(name) between 1 and 80),
  category text not null check (length(category) between 1 and 48),
  image_url text,
  unit_amount integer not null check (unit_amount between 50 and 100000),
  mode text not null check (mode in ('QUICK_ADD','CUSTOMIZE')),
  groups jsonb not null default '[]' check (jsonb_typeof(groups)='array'),
  available boolean not null default true
);
create index app_business_products_menu_idx on public.app_business_products(business_id, available, category, name);

create table public.app_business_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.app_businesses(id),
  buyer_id uuid not null references auth.users(id),
  request_id uuid not null,
  request_lines jsonb not null,
  lines jsonb not null,
  business_name text not null,
  pickup_address text not null,
  latitude double precision not null,
  longitude double precision not null,
  location_updated_at timestamptz not null,
  subtotal integer not null,
  tax integer not null,
  fee integer not null default 0,
  total integer not null check (total = subtotal + tax + fee),
  currency text not null default 'USD' check (currency = 'USD'),
  stripe_mode text not null check (stripe_mode in ('test','live')),
  connected_account_id text not null,
  intent_id text unique,
  charge_id text unique,
  processing_fee integer,
  refund_id text unique,
  refund_requested_at timestamptz,
  refunded_amount integer not null default 0,
  pickup_token uuid not null unique default gen_random_uuid(),
  status text not null default 'awaiting_payment' check (status in
    ('awaiting_payment','received','accepted','preparing','ready','completed','cancelled',
     'refund_pending','refunded','payment_review')),
  created_at timestamptz not null default now(),
  unique (buyer_id, request_id)
);
create index app_business_orders_owner_queue_idx on public.app_business_orders(business_id, created_at desc);
create index app_business_orders_buyer_history_idx on public.app_business_orders(buyer_id, created_at desc);
create table public.app_business_order_events (
  id bigint generated always as identity primary key,
  order_id uuid not null references public.app_business_orders(id),
  actor_id uuid references auth.users(id),
  status text not null,
  created_at timestamptz not null default now()
);
create index app_business_order_events_history_idx on public.app_business_order_events(order_id, id);

alter table public.app_businesses enable row level security;
alter table public.app_business_products enable row level security;
alter table public.app_business_orders enable row level security;
alter table public.app_business_order_events enable row level security;
revoke all on public.app_businesses, public.app_business_products, public.app_business_orders, public.app_business_order_events from public, anon, authenticated;
grant select, insert, update on public.app_businesses, public.app_business_products, public.app_business_orders to service_role;
grant select, insert on public.app_business_order_events to service_role;
grant usage on sequence public.app_business_order_events_id_seq to service_role;

create function public.captro_business_discover(p_lat double precision, p_lon double precision, p_offset integer)
returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(to_jsonb(b) - 'owner_id' - 'tax_bps'), '[]')
  from (
    select b.*, case when p_lat is not null and p_lon is not null then
      3958.76 * acos(least(1., greatest(-1., sin(radians(p_lat)) * sin(radians(b.latitude)) +
        cos(radians(p_lat)) * cos(radians(b.latitude)) * cos(radians(b.longitude - p_lon)))))
      end as distance_miles
    from public.app_businesses b where b.published
    order by distance_miles nulls last, b.name, b.id limit 30 offset p_offset
  ) b;
$$;

create function public.captro_business_price(p_business uuid, p_lines jsonb)
returns jsonb language plpgsql set search_path = '' as $$
declare
  shop public.app_businesses; product public.app_business_products;
  line jsonb; grp jsonb; opt jsonb; chosen jsonb; snapshots jsonb := '[]'; labels jsonb;
  quantity integer; units integer := 0; count_options integer; found_options integer; unit integer;
  subtotal integer := 0; tax integer;
begin
  select * into shop from public.app_businesses where id = p_business for share;
  if not found or not shop.published or shop.paused or shop.tax_bps is null then
    raise exception 'BUSINESS_UNAVAILABLE';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array' or jsonb_array_length(p_lines) not between 1 and 40 then
    raise exception 'INVALID_BAG';
  end if;
  for line in select value from jsonb_array_elements(p_lines) loop
    quantity := (line->>'quantity')::integer;
    units := units + quantity;
    chosen := line->'option_ids';
    if quantity is null or quantity not between 1 and 20 or units > 60
      or jsonb_typeof(chosen) is distinct from 'array' or jsonb_array_length(chosen) > 30 then
      raise exception 'INVALID_BAG';
    end if;
    select * into product from public.app_business_products
      where id = (line->>'product_id')::uuid and business_id = shop.id and available for share;
    if not found then raise exception 'PRODUCT_UNAVAILABLE'; end if;
    found_options := 0;
    unit := product.unit_amount;
    labels := '[]';
    if product.mode = 'CUSTOMIZE' then
      for grp in select value from jsonb_array_elements(product.groups) loop
        count_options := 0;
        for opt in select value from jsonb_array_elements(grp->'options') loop
          if chosen ? (opt->>'id') then
            count_options := count_options + 1;
            unit := unit + (opt->>'extra')::integer;
            labels := labels || jsonb_build_array(opt->>'name');
          end if;
        end loop;
        if count_options not between (grp->>'minimum')::integer and (grp->>'maximum')::integer then
          raise exception 'INVALID_OPTIONS';
        end if;
        found_options := found_options + count_options;
      end loop;
    end if;
    if found_options <> jsonb_array_length(chosen) then raise exception 'INVALID_OPTIONS'; end if;
    snapshots := snapshots || jsonb_build_array(jsonb_build_object('product_id', product.id,
      'name', product.name, 'image_url', product.image_url, 'quantity', quantity, 'unit_amount', unit,
      'options', labels, 'option_ids', chosen));
    subtotal := subtotal + unit * quantity;
  end loop;
  if subtotal > 50000 then raise exception 'BAG_LIMIT'; end if;
  tax := round(subtotal::numeric * shop.tax_bps / 10000)::integer;
  return jsonb_build_object('lines', snapshots, 'subtotal', subtotal, 'tax', tax, 'fee', 0, 'total', subtotal + tax);
end;
$$;

create function public.captro_business_begin(p_business uuid, p_buyer uuid, p_request uuid,
  p_lines jsonb, p_total integer, p_mode text, p_account text)
returns jsonb language plpgsql set search_path = '' as $$
declare o public.app_business_orders; shop public.app_businesses; price jsonb;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_buyer::text || ':' || p_request::text, 0));
  select * into o from public.app_business_orders where buyer_id=p_buyer and request_id=p_request;
  if found then
    if o.business_id <> p_business or o.request_lines <> p_lines or o.total <> p_total or o.stripe_mode <> p_mode then
      raise exception 'REQUEST_MISMATCH';
    end if;
    return to_jsonb(o);
  end if;
  select * into shop from public.app_businesses where id=p_business for share;
  if not found or shop.owner_id=p_buyer then raise exception 'BUSINESS_UNAVAILABLE'; end if;
  price := public.captro_business_price(p_business, p_lines);
  if (price->>'total')::integer is distinct from p_total then raise exception 'PRICE_CHANGED'; end if;
  insert into public.app_business_orders (business_id,buyer_id,request_id,request_lines,lines,business_name,
    pickup_address,latitude,longitude,location_updated_at,subtotal,tax,fee,total,stripe_mode,connected_account_id)
  values (shop.id,p_buyer,p_request,p_lines,price->'lines',shop.name,shop.pickup_address,shop.latitude,
    shop.longitude,shop.location_updated_at,(price->>'subtotal')::integer,(price->>'tax')::integer,
    (price->>'fee')::integer,p_total,p_mode,p_account) returning * into o;
  insert into public.app_business_order_events(order_id,actor_id,status) values(o.id,p_buyer,o.status);
  return to_jsonb(o);
end;
$$;

create function public.captro_business_transition(p_order uuid, p_actor uuid, p_action text, p_token uuid)
returns jsonb language plpgsql set search_path = '' as $$
declare o public.app_business_orders; owner_id uuid; next_status text;
begin
  select * into o from public.app_business_orders where id=p_order for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  select b.owner_id into owner_id from public.app_businesses b where b.id=o.business_id;
  if p_actor=owner_id then
    next_status := case
      when p_action='accept' and o.status='received' then 'accepted'
      when p_action='prepare' and o.status='accepted' then 'preparing'
      when p_action='ready' and o.status='preparing' then 'ready'
      when p_action='reject' and o.status='received' then 'refund_pending'
      when p_action='pickup' and o.status='ready' and o.pickup_token=p_token then 'completed'
    end;
  elsif p_actor=o.buyer_id and p_action='cancel' and o.status='received' then
    next_status := 'refund_pending';
  end if;
  if o.status='refund_pending' and ((p_actor=owner_id and p_action='reject') or
    (p_actor=o.buyer_id and p_action='cancel')) then return to_jsonb(o); end if;
  if next_status is null then raise exception 'INVALID_ORDER_ACTION'; end if;
  update public.app_business_orders set status=next_status,
    refund_requested_at=case when next_status='refund_pending' then now() else refund_requested_at end
    where id=o.id returning * into o;
  insert into public.app_business_order_events(order_id,actor_id,status) values(o.id,p_actor,o.status);
  return to_jsonb(o);
end;
$$;

create function public.captro_business_payment(p_order uuid, p_intent text, p_charge text, p_total integer,
  p_currency text, p_mode text, p_fee integer, p_refunded integer, p_disputed boolean)
returns jsonb language plpgsql set search_path = '' as $$
declare o public.app_business_orders; next_status text; seller uuid;
begin
  select * into o from public.app_business_orders where id=p_order for update;
  if not found or o.total<>p_total or o.currency<>p_currency or o.stripe_mode<>p_mode
    or (o.intent_id is not null and o.intent_id<>p_intent)
    or (o.charge_id is not null and o.charge_id<>p_charge)
    or p_refunded is null or p_fee not between 0 and o.total or p_refunded not between 0 and o.total then
    raise exception 'PAYMENT_MISMATCH';
  end if;
  select owner_id into seller from public.app_businesses where id=o.business_id;
  next_status := case
    when greatest(p_refunded, o.refunded_amount)=o.total then 'refunded'
    when p_disputed or p_refunded>0 or o.refunded_amount>0 then 'payment_review'
    when o.status='awaiting_payment' then 'received'
    when o.status='cancelled' then 'payment_review'
    else o.status end;
  insert into public.app_marketplace_ledger(entry_key,seller_id,event_type,account,amount,currency,stripe_object_id,metadata)
    values ('business:'||o.id||':gross',seller,'BUSINESS_CUSTOMER_PAYMENT','gross',o.total,o.currency,p_charge,
      jsonb_build_object('business_order_id',o.id,'stripe_mode',o.stripe_mode))
    on conflict(entry_key) do nothing;
  if p_fee is not null then
    insert into public.app_marketplace_ledger(entry_key,seller_id,event_type,account,amount,currency,stripe_object_id,metadata)
    values ('business:'||o.id||':fee',seller,'BUSINESS_PROCESSING_FEE','processing_fee',p_fee,o.currency,p_charge,
      jsonb_build_object('business_order_id',o.id,'stripe_mode',o.stripe_mode))
    on conflict(entry_key) do nothing;
  end if;
  if p_refunded>o.refunded_amount then
    insert into public.app_marketplace_ledger(entry_key,seller_id,event_type,account,amount,currency,stripe_object_id,metadata)
    values ('business:'||o.id||':refund:'||p_refunded,seller,'BUSINESS_REFUND','gross',o.refunded_amount-p_refunded,
      o.currency,p_charge,jsonb_build_object('business_order_id',o.id,'stripe_mode',o.stripe_mode))
    on conflict(entry_key) do nothing;
  end if;
  if next_status<>o.status then
    insert into public.app_business_order_events(order_id,status) values(o.id,next_status);
  end if;
  update public.app_business_orders set status=next_status,intent_id=p_intent,charge_id=p_charge,
    processing_fee=coalesce(processing_fee,p_fee),refunded_amount=greatest(p_refunded,refunded_amount) where id=o.id returning * into o;
  return to_jsonb(o);
end;
$$;

create function public.captro_business_cancel_payment(p_order uuid, p_intent text)
returns jsonb language plpgsql set search_path = '' as $$
declare o public.app_business_orders;
begin
  select * into o from public.app_business_orders where id=p_order for update;
  if not found or p_intent is null or (o.intent_id is not null and o.intent_id<>p_intent) then
    raise exception 'PAYMENT_MISMATCH';
  end if;
  if o.status='awaiting_payment' then
    update public.app_business_orders set status='cancelled', intent_id=p_intent
      where id=o.id returning * into o;
    insert into public.app_business_order_events(order_id,status) values(o.id,o.status);
  end if;
  return to_jsonb(o);
end;
$$;

create function public.captro_business_earnings(p_business uuid, p_owner uuid)
returns jsonb language plpgsql stable set search_path = '' as $$
begin
  if not exists(select 1 from public.app_businesses where id=p_business and owner_id=p_owner) then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  return (select jsonb_build_object(
    'gross', coalesce(sum(total),0), 'tax', coalesce(sum(tax),0),
    'refunded', coalesce(sum(refunded_amount),0), 'processing_fee', coalesce(sum(processing_fee),0),
    'pending_fees', count(*) filter(where processing_fee is null)
  ) from public.app_business_orders where business_id=p_business and stripe_mode='test' and charge_id is not null);
end;
$$;

revoke execute on function public.captro_business_cancel_payment(uuid,text),
  public.captro_business_earnings(uuid,uuid) from public,anon,authenticated;
grant execute on function public.captro_business_cancel_payment(uuid,text),
  public.captro_business_earnings(uuid,uuid) to service_role;

revoke execute on function public.captro_business_discover(double precision,double precision,integer),
  public.captro_business_price(uuid,jsonb), public.captro_business_begin(uuid,uuid,uuid,jsonb,integer,text,text),
  public.captro_business_transition(uuid,uuid,text,uuid),
  public.captro_business_payment(uuid,text,text,integer,text,text,integer,integer,boolean) from public,anon,authenticated;
grant execute on function public.captro_business_discover(double precision,double precision,integer),
  public.captro_business_price(uuid,jsonb), public.captro_business_begin(uuid,uuid,uuid,jsonb,integer,text,text),
  public.captro_business_transition(uuid,uuid,text,uuid),
  public.captro_business_payment(uuid,text,text,integer,text,text,integer,integer,boolean) to service_role;
