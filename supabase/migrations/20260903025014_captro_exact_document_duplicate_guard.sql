create index if not exists scanned_receipts_document_hash_idx
  on public.scanned_receipts(document_sha256);

create or replace function public.captro_claim_receipt_reward_fingerprint(
  p_receipt_id uuid,
  p_user_id text,
  p_reward_fingerprint text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current public.scanned_receipts%rowtype;
  v_duplicate public.scanned_receipts%rowtype;
begin
  if p_reward_fingerprint is null or p_reward_fingerprint !~ '^[a-f0-9]{64}$' then
    raise exception 'RECEIPT_FINGERPRINT_INVALID';
  end if;
  select * into v_current from public.scanned_receipts
  where id = p_receipt_id and user_id = p_user_id;
  if not found then raise exception 'RECEIPT_NOT_FOUND'; end if;

  -- Serializes identical bytes across accounts even if provider extraction varies.
  perform pg_advisory_xact_lock(hashtextextended('captro-document-hash:' || v_current.document_sha256, 0));
  perform pg_advisory_xact_lock(hashtextextended('captro-reward-fingerprint:' || p_reward_fingerprint, 0));
  select * into v_current from public.scanned_receipts
  where id = p_receipt_id and user_id = p_user_id for update;
  if not found then raise exception 'RECEIPT_NOT_FOUND'; end if;

  select * into v_duplicate from public.scanned_receipts
  where id <> p_receipt_id
    and reward_fingerprint is not null
    and (document_sha256 = v_current.document_sha256 or reward_fingerprint = p_reward_fingerprint)
  order by created_at asc limit 1;

  if found then
    update public.scanned_receipts
    set status = 'duplicate', reward_eligible = false, duplicate_of = v_duplicate.id,
        updated_at = now(), completed_at = now()
    where id = p_receipt_id;
    return jsonb_build_object('claimed', false, 'duplicate', true);
  end if;

  update public.scanned_receipts
  set reward_fingerprint = p_reward_fingerprint, updated_at = now()
  where id = p_receipt_id;
  return jsonb_build_object('claimed', true, 'duplicate', false);
end;
$$;

revoke all on function public.captro_claim_receipt_reward_fingerprint(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.captro_claim_receipt_reward_fingerprint(uuid, text, text) to service_role;
