-- Versioned freeform NoteCanvas documents.
-- The document is kept atomic so wall preview, editor, and detail always render
-- the same saved composition. Media ownership remains in media_assets.

alter table public.wall_notes
  add column if not exists canvas_version integer not null default 1,
  add column if not exists canvas_template text,
  add column if not exists canvas_width integer,
  add column if not exists canvas_height integer,
  add column if not exists canvas_background jsonb,
  add column if not exists canvas_elements jsonb;

alter table public.wall_notes
  drop constraint if exists wall_notes_canvas_version_check,
  add constraint wall_notes_canvas_version_check
    check (canvas_version between 1 and 10),
  drop constraint if exists wall_notes_canvas_template_check,
  add constraint wall_notes_canvas_template_check
    check (
      canvas_template is null or canvas_template in (
        'journal',
        'travel_diary',
        'scrapbook',
        'notebook',
        'minimal',
        'dark_album',
        'recipe_book'
      )
    ),
  drop constraint if exists wall_notes_canvas_width_check,
  add constraint wall_notes_canvas_width_check
    check (canvas_width is null or canvas_width between 320 and 4096),
  drop constraint if exists wall_notes_canvas_height_check,
  add constraint wall_notes_canvas_height_check
    check (canvas_height is null or canvas_height between 480 and 12288),
  drop constraint if exists wall_notes_canvas_background_check,
  add constraint wall_notes_canvas_background_check
    check (canvas_background is null or jsonb_typeof(canvas_background) = 'object'),
  drop constraint if exists wall_notes_canvas_elements_check,
  add constraint wall_notes_canvas_elements_check
    check (
      canvas_elements is null or (
        jsonb_typeof(canvas_elements) = 'array'
        and jsonb_array_length(canvas_elements) between 1 and 80
      )
    );

create index if not exists wall_notes_canvas_template_idx
  on public.wall_notes (canvas_template, created_at desc)
  where status = 'active'
    and moderation_status = 'approved'
    and canvas_template is not null;

comment on column public.wall_notes.canvas_version is
  'Version of Captro normalized freeform NoteCanvas document.';
comment on column public.wall_notes.canvas_background is
  'Canvas material and texture configuration. Never contains media binaries.';
comment on column public.wall_notes.canvas_elements is
  'Ordered normalized freeform elements; media entries reference approved media_assets.';
