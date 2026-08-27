-- Product-level NoteDocument metadata for the redesigned Notes experience.
-- Canvas columns remain the renderable source of truth; these fields describe
-- how the artwork should be discovered, imported, detailed, and previewed.

alter table public.wall_notes
  add column if not exists note_schema_version integer,
  add column if not exists artwork_mode text,
  add column if not exists content_kind text,
  add column if not exists note_visibility text,
  add column if not exists document_title text,
  add column if not exists document_subtitle text,
  add column if not exists thumbnail_url text,
  add column if not exists alt_text text,
  add column if not exists detail_blocks jsonb,
  add column if not exists canvas_format text;

alter table public.wall_notes
  drop constraint if exists wall_notes_canvas_template_check,
  add constraint wall_notes_canvas_template_check
    check (
      canvas_template is null or canvas_template in (
        'blank',
        'journal',
        'personal_journal',
        'daily_note',
        'travel_diary',
        'scrapbook',
        'moodboard',
        'notebook',
        'minimal',
        'minimal_photo',
        'minimal_motivation',
        'dark_album',
        'recipe_book',
        'book_review',
        'event_poster',
        'party_invitation',
        'announcement',
        'imported_artwork'
      )
    ),
  drop constraint if exists wall_notes_note_schema_version_check,
  add constraint wall_notes_note_schema_version_check
    check (note_schema_version is null or note_schema_version between 1 and 10),
  drop constraint if exists wall_notes_artwork_mode_check,
  add constraint wall_notes_artwork_mode_check
    check (artwork_mode is null or artwork_mode in ('editable_canvas', 'imported_artwork')),
  drop constraint if exists wall_notes_content_kind_check,
  add constraint wall_notes_content_kind_check
    check (
      content_kind is null or content_kind in (
        'journal',
        'photo_collage',
        'minimal_photo',
        'travel_recap',
        'event_poster',
        'party_invitation',
        'announcement',
        'recipe',
        'book_review',
        'moodboard',
        'outfit_board',
        'birthday_page',
        'memorial_page',
        'poem',
        'quote',
        'artwork',
        'imported_design',
        'scrapbook',
        'other'
      )
    ),
  drop constraint if exists wall_notes_note_visibility_check,
  add constraint wall_notes_note_visibility_check
    check (note_visibility is null or note_visibility in ('public_wall', 'friends', 'private_draft')),
  drop constraint if exists wall_notes_canvas_format_check,
  add constraint wall_notes_canvas_format_check
    check (
      canvas_format is null or canvas_format in (
        'square',
        'portrait_4x5',
        'editorial_3x4',
        'portrait_2x3',
        'poster_9x16',
        'landscape_4x3',
        'landscape_16x9',
        'long_page'
      )
    ),
  drop constraint if exists wall_notes_detail_blocks_check,
  add constraint wall_notes_detail_blocks_check
    check (
      detail_blocks is null or (
        jsonb_typeof(detail_blocks) = 'array'
        and jsonb_array_length(detail_blocks) <= 24
      )
    );

create index if not exists wall_notes_document_discovery_idx
  on public.wall_notes (content_kind, created_at desc)
  where status = 'active'
    and moderation_status = 'approved'
    and content_kind is not null;

create index if not exists wall_notes_artwork_mode_idx
  on public.wall_notes (artwork_mode, created_at desc)
  where status = 'active'
    and moderation_status = 'approved'
    and artwork_mode is not null;

comment on column public.wall_notes.artwork_mode is
  'How the note artwork was authored: editable Captro canvas or imported finished artwork.';
comment on column public.wall_notes.content_kind is
  'Discovery/category hint for visual notes such as recipe, event poster, book review, or imported design.';
comment on column public.wall_notes.detail_blocks is
  'Optional structured Note Detail sections for events, recipes, reviews, memories, and links.';
comment on column public.wall_notes.canvas_format is
  'Selected artwork aspect format used by wall masonry and detail rendering.';
