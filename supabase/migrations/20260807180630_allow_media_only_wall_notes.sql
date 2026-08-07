-- Media-only photo and voice notes are valid Wall entries. Text notes still
-- require written content, and every note remains capped at 300 characters.

alter table public.wall_notes
  drop constraint if exists wall_notes_body_check;

alter table public.wall_notes
  add constraint wall_notes_body_check
    check (
      char_length(body) <= 300
      and (note_type <> 'text' or char_length(body) >= 1)
    );
