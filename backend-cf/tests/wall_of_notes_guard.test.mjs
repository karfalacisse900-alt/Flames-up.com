import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { test } from 'node:test';

const repoRoot = path.resolve(import.meta.dirname, '..', '..');

async function read(relativePath) {
  return readFile(path.join(repoRoot, relativePath), 'utf8');
}

test('wall routes are authenticated, global-only, and Ghost-safe', async () => {
  const worker = await read('backend-cf/src/index.ts');

  assert.match(worker, /api\.get\('\/wall\/notes', authMiddleware/);
  assert.match(worker, /api\.post\('\/wall\/notes', authMiddleware/);
  assert.match(worker, /api\.get\('\/wall\/overview', authMiddleware/);
  assert.match(worker, /world_x\.gte/);
  assert.match(worker, /identity === 'author' \? \{/);
  assert.match(worker, /author_preview: identity === 'author'/);
  assert.match(worker, /enforceRateLimit\(c, 'wall_note_create'/);
  assert.match(worker, /moderateCommunityText\(body\)/);
  assert.match(
    worker,
    /resolveWallNotePlacement\(\s*c,\s*wallId,\s*placementWidth,\s*placementHeight,\s*noteId,?\s*\)/,
  );
  assert.match(worker, /const placementScale = mediaAsset \? 1\.34 : requestedType === 'voice' \? 1\.18 : 1\.27/);
  assert.match(worker, /claimWallPlacementSlot\(c, wallId\)/);
  assert.match(worker, /overlap <= 0\.10/);
  assert.match(worker, /const WALLS = new Map\(\[\['global', 'Global'\]\]\)/);
  assert.match(worker, /function normalizedWallId\(_value: unknown\): string \{[\s\S]*return 'global'/);
  assert.doesNotMatch(worker, /wall_id: cleanText\(b\.wall_id/);
});

test('Wall author hydration cannot query the removed app_users status column', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const start = worker.indexOf('async function supabaseUsersByAnyIds');
  const end = worker.indexOf('async function supabaseBlockedUserIds', start);
  const helper = worker.slice(start, end);
  const wallStart = worker.indexOf("api.get('/wall/notes'");
  const wallEnd = worker.indexOf("api.get('/wall/overview'", wallStart);
  const wallRoute = worker.slice(wallStart, wallEnd);

  assert.doesNotMatch(helper, /is_verified,status,counts/);
  assert.match(helper, /is_verified,counts,profile,metadata/);
  assert.match(wallRoute, /supabaseUsersByAnyIds\(c, ownerIds\)/);
  assert.match(wallRoute, /supabaseUserStatus\(author\) === 'active'/);
});

test('wall migration has RLS, spatial indexes, and unique interaction keys', async () => {
  const migration = await read('supabase/migrations/20260712025734_wall_of_notes.sql');

  for (const table of ['wall_notes', 'wall_note_reactions', 'wall_note_saves', 'wall_note_replies']) {
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`, 'i'));
  }
  assert.match(migration, /primary key \(note_id, app_user_id\)/i);
  assert.match(migration, /wall_notes_region_idx/i);
  assert.match(migration, /char_length\(body\) between 1 and 300/i);
});

test('wall layout migration preserves history and exposes aggregate framing only to the Worker', async () => {
  const migration = await read('supabase/migrations/20260712141739_wall_layout_polish.sql');

  assert.match(migration, /layout_version', 'growing_cluster_v1'/i);
  assert.match(migration, /create or replace function public\.captro_wall_overview/i);
  assert.match(migration, /create or replace function public\.captro_claim_wall_slot/i);
  assert.match(migration, /for update/i);
  assert.match(migration, /grant execute on function public\.captro_wall_overview\(text\) to service_role/i);
  assert.match(migration, /revoke all on function public\.captro_wall_overview\(text\) from public, anon, authenticated/i);
});
test('wall API preserves stable mixed-media presentation metadata', async () => {
  const worker = await read('backend-cf/src/index.ts');

  for (const style of ['sticky', 'editorial', 'handwritten', 'poster', 'polaroid', 'receipt', 'torn_paper', 'notebook', 'postcard', 'minimal']) {
    assert.match(worker, new RegExp(`'${style}'`));
  }
  assert.match(worker, /const metadata = parseJsonObject\(row\?\.metadata\)/);
  assert.match(worker, /media_url: cleanText\(metadata\.media_url/);
  assert.match(worker, /media_thumbnail_url: cleanText\(metadata\.media_thumbnail_url \|\| metadata\.media_url/);
  assert.match(worker, /layout_version: noteDocument \? 'note_document_v1' : noteCanvas \? 'note_canvas_v1' : 'living_wall_v1'/);
  assert.match(worker, /document: wallNoteDocumentPayload\(row, canvas\)/);
  assert.match(worker, /canvas_format: noteCanvas\?\.format \?\? null/);
  assert.match(worker, /note_schema_version: noteDocument\?\.schema_version/);
  assert.match(worker, /canvas_version: noteCanvas\?\.version \?\? 1/);
  assert.match(worker, /canvas_template: noteCanvas\?\.template \?\? null/);
  assert.match(worker, /canvas_elements: noteCanvas\?\.elements \?\? null/);
  assert.doesNotMatch(worker, /media_url:\s*['"]https?:\/\//);
});

test('NoteDocument metadata is additive, bounded, and migration-backed', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const migration = await read('supabase/migrations/20260816143000_wall_note_document_metadata.sql');

  assert.match(worker, /function normalizeWallNoteDocument/);
  assert.match(worker, /const WALL_NOTE_ARTWORK_MODES = new Set\(\['editable_canvas', 'imported_artwork'\]\)/);
  assert.match(worker, /const WALL_NOTE_CONTENT_KINDS = new Set/);
  assert.match(worker, /const WALL_NOTE_DETAIL_BLOCK_KINDS = new Set/);
  assert.match(worker, /normalizeWallNoteDetailBlocks\(source\.detail_blocks \|\| source\.detailBlocks\)/);
  assert.match(worker, /detail_blocks: noteDocument\?\.detail_blocks \?\? null/);
  assert.match(worker, /wallNoteCanvasFormatForSize/);
  assert.match(migration, /add column if not exists artwork_mode text/i);
  assert.match(migration, /add column if not exists content_kind text/i);
  assert.match(migration, /add column if not exists detail_blocks jsonb/i);
  assert.match(migration, /add column if not exists canvas_format text/i);
  assert.match(migration, /'event_poster'/i);
  assert.match(migration, /'imported_artwork'/i);
  assert.match(migration, /jsonb_array_length\(detail_blocks\) <= 24/i);
});

test('photo notes require an approved user-owned Cloudflare Images asset', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const migration = await read('supabase/migrations/20260807180630_allow_media_only_wall_notes.sql');

  assert.match(worker, /requestedType === 'text' && !body/);
  assert.doesNotMatch(worker, /requestedType !== 'voice' && !body/);
  assert.match(migration, /note_type <> 'text' or char_length\(body\) >= 1/i);
  assert.match(worker, /submittedMediaUrl && !mediaAssetId/);
  assert.match(worker, /const canvasPhotoAssetIds:[\s\S]*?element\.kind === 'photo' \|\| element\.kind === 'polaroid'/);
  assert.match(worker, /drawing_name: cleanText\(rawStyle\.drawing_name \|\| rawStyle\.drawingName/);
  assert.match(worker, /approvedMediaAssetsForPost\(c, userId, mediaAssetIds, \[\]\)/);
  assert.match(worker, /const invalidAsset = mediaAssets\.find/);
  assert.match(worker, /normalizeMediaAssetType\(asset\?\.media_type\) !== 'image'/);
  assert.match(worker, /cleanText\(asset\?\.storage_provider, 40\) !== 'images'/);
  assert.match(worker, /const assetsById = new Map/);
  assert.match(worker, /media_url: trustedUrl \|\| null/);
  assert.match(worker, /const unresolvedCanvasPhoto = noteCanvas\.elements\.find/);
  assert.match(worker, /const resolvedStyleToken = WALL_NOTE_STYLES\.has\(styleToken\)/);
  assert.match(worker, /style_token: resolvedStyleToken/);
  assert.match(worker, /canvas_elements: noteCanvas\?\.elements \?\? null/);
  assert.match(worker, /const assetsToLink = mediaAssets\.length \? mediaAssets : \[voiceAsset\]/);
  assert.match(worker, /wall_note_id: noteId/);
});

test('Captro Studio publishes its rendered image through the canonical Wall create path', async () => {
  const studio = await read('ios_native/MIRA/Sources/MIRANative/Screens/MIRACaptroStudioView.swift');
  const wallView = await read('ios_native/MIRA/Sources/MIRANative/Screens/WallOfNotesNativeView.swift');

  assert.match(studio, /let uploader = MIRAMediaUploadService\(api: api\)/);
  assert.match(studio, /for \(index, key\) in mediaKeys\.enumerated\(\)/);
  assert.match(studio, /uploaded\[key\] = try await uploader\.uploadResult\(picked\)/);
  assert.match(studio, /let canvas = makeNoteCanvas\(document: document, uploads: uploads\)/);
  assert.match(studio, /let noteDocument = makeNoteDocument/);
  assert.match(studio, /body: canvasText/);
  assert.match(studio, /noteType: uploads\.isEmpty \? "text" : "photo"/);
  assert.match(studio, /document: noteDocument/);
  assert.match(studio, /canvas: canvas/);
  assert.match(studio, /_ = try await onPublish\(request\)/);
  assert.match(wallView, /MIRANoteCreationEntryView\(camera: camera, api: api\)/);
  assert.match(wallView, /Upload design/);
  assert.match(wallView, /template: \.importedArtwork/);
  assert.match(wallView, /document: document/);
  assert.match(wallView, /canvasDetailBlocks\(blocks\)/);
  assert.match(wallView, /MIRACaptroStudioView\(camera: camera, api: api, initialTemplate: studioInitialTemplate\)[\s\S]*?let note = try await model\.create\(body\)/);
  assert.match(wallView, /func create\(_ body: MIRACreateWallNoteBody\)[\s\S]*?merge\(\[response\.note\]/);
});

test('living Wall features are migration-backed and cannot bypass Worker moderation', async () => {
  const migration = await read('supabase/migrations/20260727130135_wall_note_living_features.sql');

  assert.match(migration, /note_type in \('text', 'photo', 'voice'\)/i);
  assert.match(migration, /primary key \(note_id, app_user_id\)/i);
  assert.match(migration, /alter table public\.wall_note_signatures enable row level security/i);
  assert.match(migration, /alter table public\.wall_note_contributions enable row level security/i);
  assert.match(migration, /grant select on public\.wall_note_signatures to authenticated/i);
  assert.match(migration, /grant select on public\.wall_note_contributions to authenticated/i);
  assert.doesNotMatch(migration, /grant [^;]*(insert|update|delete)[^;]*wall_note_(signatures|contributions)/i);
  assert.match(migration, /case when tg_op = 'DELETE' then old\.note_id else new\.note_id end/i);
  assert.match(migration, /jsonb_array_length\(voice_waveform\) <= 48/i);
});

test('voice notes are validated, transcribed, moderated, and never retain transcript text', async () => {
  const worker = await read('backend-cf/src/index.ts');

  assert.match(worker, /detectAudioContentType\(audioBytes\)/);
  assert.match(worker, /@cf\/openai\/whisper/);
  assert.match(worker, /moderateWallVoiceUpload\(c\.env, audioBytes\)/);
  assert.match(worker, /transcript_sha256: input\.moderation\.transcriptHash/);
  assert.match(worker, /transcript_retained: false/);
  assert.match(worker, /moderation_status: 'approved'/);
  assert.match(worker, /supabaseUserIsActive\(signers\.get/);
  assert.match(worker, /next_after:/);
});

test('Wall locations are retired end to end while legacy clients remain compatible', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const wallView = await read('ios_native/MIRA/Sources/MIRANative/Screens/WallOfNotesNativeView.swift');
  const migration = await read('supabase/migrations/20260806132124_wall_global_only.sql');

  assert.match(worker, /wall_id: 'global'/);
  assert.match(worker, /location: null/);
  assert.match(worker, /location_label: null/);
  assert.match(worker, /approximate_location: null/);
  assert.doesNotMatch(wallView, /MIRAWallApproximateLocationProvider/);
  assert.doesNotMatch(wallView, /FOUND NEARBY/);
  assert.doesNotMatch(wallView, /localRecommendation/);
  assert.match(wallView, /Label\("More options", systemImage: "slider\.horizontal\.3"\)/);
  assert.match(migration, /check \(wall_id = 'global'\) not valid/i);
  assert.match(migration, /location_visibility = false/i);
});

test('Wall detail collections use bounded cursor pagination and deduplicate appended rows', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const wallView = await read('ios_native/MIRA/Sources/MIRANative/Screens/WallOfNotesNativeView.swift');

  assert.match(worker, /next_before:/);
  assert.match(worker, /next_after:/);
  assert.match(wallView, /URLQueryItem\(name: "before", value: before\)/);
  assert.match(wallView, /URLQueryItem\(name: "after", value: after\)/);
  assert.match(wallView, /mergingUnique\(contributions, response\.contributions, id: \\.id\)/);
  assert.match(wallView, /mergingUnique\(pageSigners, response\.signers, id: \\.id\)/);
  assert.match(wallView, /mergingUnique\(signers, pageSigners, id: \\.id\)/);
});

test('Wall voice playback preserves position across app lifecycle and stops when detail closes', async () => {
  const voiceSupport = await read('ios_native/MIRA/Sources/MIRANative/Services/MIRAWallVoiceSupport.swift');
  const wallView = await read('ios_native/MIRA/Sources/MIRANative/Screens/WallOfNotesNativeView.swift');

  assert.match(voiceSupport, /AVAudioSession\.interruptionNotification/);
  assert.match(voiceSupport, /UIApplication\.didEnterBackgroundNotification/);
  assert.match(voiceSupport, /UIApplication\.didBecomeActiveNotification/);
  assert.match(voiceSupport, /self\?\.pauseForBackground\(\)/);
  assert.match(voiceSupport, /self\?\.resumeAfterForegroundIfNeeded\(\)/);
  assert.match(voiceSupport, /private func pausePreservingPlayback\(\)/);
  assert.match(voiceSupport, /private func resumePreservingPlayback\(\)/);
  assert.match(wallView, /\.onDisappear\s*\{\s*voicePlayback\.stop\(\)\s*\}/);
  assert.match(wallView, /UIApplication\.openSettingsURLString/);
});

test('Wall gallery taps, exact-canvas lift, flipping, and signatures remain explicit and reachable', async () => {
  const wallView = await read('ios_native/MIRA/Sources/MIRANative/Screens/WallOfNotesNativeView.swift');
  const renderer = await read('ios_native/MIRA/Sources/MIRANative/Components/MIRAWallNoteRenderer.swift');
  const signatureCanvas = await read('ios_native/MIRA/Sources/MIRANative/Components/MIRAWallSignatureCanvas.swift');

  assert.match(wallView, /private func editorialRows\(for notes: \[MIRAWallNote\]\)/);
  assert.match(wallView, /note\.resolvedCanvas\?\.aspectRatio/);
  assert.match(wallView, /ScrollView \{/);
  assert.match(wallView, /onTapGesture\s*\{\s*openNote\(note\)\s*\}/);
  assert.match(wallView, /DragGesture\(minimumDistance: 6, coordinateSpace: \.local\)/);
  assert.doesNotMatch(wallView, /DragGesture\(minimumDistance: 0, coordinateSpace: \.local\)/);
  assert.match(wallView, /Turn note over/);
  assert.match(wallView, /Sign this note/);
  assert.match(wallView, /MIRAWallDetailBackdrop\(seed: note\.id\)/);
  assert.match(wallView, /MIRAWallSignatureCaptureView\(/);
  assert.match(signatureCanvas, /DragGesture\(minimumDistance: 0, coordinateSpace: \.local\)/);
  assert.match(signatureCanvas, /MIRAWallSignatureInkView\(drawing: drawing/);
  assert.match(wallView, /@Namespace private var noteCanvasTransition/);
  assert.match(wallView, /id: "wall-note-\\\(note\.id\)"/);
  assert.match(wallView, /transitionNamespace: noteCanvasTransition/);
  assert.match(wallView, /isSource: true/);
  assert.match(wallView, /isSource: false/);
  assert.doesNotMatch(renderer, /matchedGeometryEffect/);
});

test('drawn Wall signatures are bounded, validated, and migration-backed', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const migration = await read('supabase/migrations/20260806120017_wall_note_drawn_signatures.sql');

  assert.match(worker, /function normalizeWallSignatureDrawing/);
  assert.match(worker, /source\.strokes\.length < 1 \|\| source\.strokes\.length > 12/);
  assert.match(worker, /stroke\.points\.length < 2 \|\| stroke\.points\.length > 180/);
  assert.match(worker, /pointCount > 600/);
  assert.match(worker, /rejectLargeRequest\(c, 18_000\)/);
  assert.match(worker, /signature_strokes: drawing/);
  assert.match(worker, /SIGNATURE_DRAWING_REQUIRED/);
  assert.match(migration, /add column if not exists signature_strokes jsonb not null/i);
  assert.match(migration, /jsonb_array_length\(signature_strokes -> 'strokes'\) <= 12/i);
  assert.match(migration, /octet_length\(signature_strokes::text\) <= 20000/i);
});

test('photo-note detail opens at the selected print and keeps creator browsing privacy scoped', async () => {
  const worker = await read('backend-cf/src/index.ts');
  const wallView = await read('ios_native/MIRA/Sources/MIRANative/Screens/WallOfNotesNativeView.swift');

  assert.match(worker, /const authorUserId = publicId\(c\.req\.query\('author_user_id'\)/);
  assert.match(worker, /filters\.author_account_id = postgrestEqFilter\(authorUserId\)/);
  assert.match(worker, /filters\.publishing_identity = postgrestEqFilter\('author'\)/);
  assert.match(wallView, /func creatorNotes\(authorUserID:/);
  assert.match(wallView, /photoScrapbookSpread/);
  assert.match(wallView, /\.defaultScrollAnchor\(\.top\)/);
  assert.match(wallView, /proxy\.scrollTo\("note-detail-top", anchor: \.top\)/);
  assert.match(wallView, /ScrollView\(\.horizontal, showsIndicators: false\)/);
  assert.match(wallView, /selectCreatorNote\(candidate\)/);
  assert.doesNotMatch(wallView, /LazyVGrid\([\s\S]{0,1600}relatedPhotoNotes/);
});
