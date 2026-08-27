begin;

alter table public.wall_note_signatures
  add column if not exists signature_strokes jsonb not null
  default '{"version":1,"strokes":[]}'::jsonb;

alter table public.wall_note_signatures
  drop constraint if exists wall_note_signatures_strokes_shape_check;

alter table public.wall_note_signatures
  add constraint wall_note_signatures_strokes_shape_check
  check (
    jsonb_typeof(signature_strokes) = 'object'
    and signature_strokes ->> 'version' = '1'
    and jsonb_typeof(signature_strokes -> 'strokes') = 'array'
    and jsonb_array_length(signature_strokes -> 'strokes') <= 12
    and octet_length(signature_strokes::text) <= 20000
  );

comment on column public.wall_note_signatures.signature_strokes is
  'Compact normalized finger-drawn signature strokes. The Worker validates coordinates, stroke count, point count, and payload size.';

commit;
