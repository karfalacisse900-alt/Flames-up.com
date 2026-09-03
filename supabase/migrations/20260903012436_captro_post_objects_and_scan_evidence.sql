alter table public.scanned_receipts
  add column if not exists verification_checks jsonb not null default '[]'::jsonb,
  add column if not exists failure_code text;

-- Public summaries are explicitly attached by the server. Private originals never
-- become post media, and issuer credentials/ticket holders live in a separate table.
create table public.app_post_objects (
  post_id uuid primary key references public.app_posts(id) on delete cascade,
  kind text not null check (kind in ('place', 'event', 'travel', 'receipt', 'invoice', 'collection')),
  public_data jsonb not null default '{}'::jsonb check (jsonb_typeof(public_data) = 'object'),
  receipt_id uuid references public.scanned_receipts(id) on delete set null,
  created_at timestamptz not null default now()
);
create index app_post_objects_receipt_idx on public.app_post_objects(receipt_id) where receipt_id is not null;

create table public.app_post_tickets (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.app_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  issuer_reference text not null,
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  private_storage_path text,
  status text not null default 'active' check (status in ('active', 'revoked', 'used')),
  created_at timestamptz not null default now(),
  unique(post_id, user_id, issuer_reference)
);
create index app_post_tickets_owner_idx on public.app_post_tickets(user_id, post_id);

create table public.app_post_attendance (
  post_id uuid not null references public.app_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index app_post_attendance_user_idx on public.app_post_attendance(user_id);

alter table public.app_post_objects enable row level security;
alter table public.app_post_tickets enable row level security;
alter table public.app_post_attendance enable row level security;
revoke all on public.app_post_objects, public.app_post_tickets, public.app_post_attendance from anon, authenticated;
grant all on public.app_post_objects, public.app_post_tickets, public.app_post_attendance to service_role;

comment on table public.app_post_objects is 'Server-managed, explicitly published object summaries. No private ticket or receipt payloads.';
comment on table public.app_post_tickets is 'Issuer-backed tickets; accessible only through owner-authorized backend routes, never feed payloads.';
