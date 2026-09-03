-- Correct legacy approvals inferred from absent fraud flags. Existing credits and
-- completed feedback remain untouched; only verification evidence is repaired.
with risk_results as (
  select id,
    lower(trim(coalesce(extracted_data #>> '{signals,decision}', ''))) as decision,
    lower(trim(coalesce(extracted_data #>> '{signals,color}', ''))) as color
  from public.scanned_receipts
  where provider_request_id is not null
), corrections as (
  select id,
    case when decision in ('fraud', 'red', 'declined', 'deny', 'denied', 'fail', 'failed', 'rejected')
      or color = 'red' then 'failed' else 'unavailable' end as check_status
  from risk_results
  where color in ('red', 'yellow')
    or decision not in ('green', 'not fraud', 'accept', 'accepted', 'pass', 'passed', 'verified')
      and not (decision = '' and color = 'green')
)
update public.scanned_receipts as receipt
set verification_status = 'couldnt_verify',
    reward_eligible = false,
    status = case when receipt.status = 'feedback_pending' then 'review_ready' else receipt.status end,
    verification_checks = coalesce((
      select jsonb_agg(check_item order by position)
      from jsonb_array_elements(coalesce(receipt.verification_checks, '[]'::jsonb))
        with ordinality as checks(check_item, position)
      where check_item->>'key' <> 'provider_document_signal'
    ), '[]'::jsonb) || jsonb_build_array(jsonb_build_object(
      'key', 'provider_document_signal',
      'status', corrections.check_status,
      'detail', 'The stored provider result did not confirm an acceptable document-risk assessment.'
    )),
    updated_at = now()
from corrections
where receipt.id = corrections.id
  and (receipt.verification_status = 'verified' or receipt.reward_eligible
    or receipt.verification_checks @> '[{"key":"provider_document_signal","status":"passed"}]'::jsonb);
