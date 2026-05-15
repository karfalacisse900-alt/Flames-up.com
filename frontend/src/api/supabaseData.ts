import { supabase, isSupabaseConfigured } from './supabase';

type AppUser = {
  id?: string;
  email?: string;
  username?: string;
  full_name?: string;
  profile_image?: string;
  bio?: string;
  is_private?: boolean;
};

type DocumentVisibility = 'public' | 'followers' | 'friends' | 'private';

function cleanString(value: unknown, max = 500) {
  return String(value || '').trim().slice(0, max);
}

function safeDocumentKey(value: unknown, fallback = '') {
  const raw = cleanString(value || fallback, 160);
  return raw
    .toLowerCase()
    .replace(/[^a-z0-9._:-]/g, '-')
    .replace(/-+/g, '-')
    .slice(0, 160);
}

async function currentSupabaseUserId() {
  if (!isSupabaseConfigured()) return '';
  const { data } = await supabase.auth.getSession();
  return data.session?.user?.id || '';
}

export async function upsertSupabaseProfile(user: AppUser | null | undefined) {
  const supabaseUserId = await currentSupabaseUserId();
  if (!supabaseUserId || !user) return;

  await supabase.from('profiles').upsert({
    id: supabaseUserId,
    app_user_id: cleanString(user.id, 120) || null,
    email: cleanString(user.email, 320) || null,
    username: cleanString(user.username, 60) || null,
    full_name: cleanString(user.full_name, 120) || null,
    avatar_url: cleanString(user.profile_image, 1200) || null,
    bio: cleanString(user.bio, 500) || null,
    is_private: !!user.is_private,
    metadata: {
      source: 'flames_backend_bridge',
      app_user_id: user.id || null,
    },
    updated_at: new Date().toISOString(),
  }, { onConflict: 'id' });
}

function normalizeJsonArray(value: unknown) {
  if (Array.isArray(value)) return value;
  if (typeof value === 'string' && value.trim()) {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? parsed : [];
    } catch {
      return [];
    }
  }
  return [];
}

function buildSupabaseMedia(post: any, fallback: any) {
  const urls = normalizeJsonArray(post?.images?.length ? post.images : fallback?.images);
  const mediaTypes = normalizeJsonArray(post?.media_types?.length ? post.media_types : fallback?.media_types);
  const dimensions = normalizeJsonArray(post?.media_dimensions?.length ? post.media_dimensions : fallback?.media_dimensions);
  const firstUrl = post?.image || fallback?.image || urls[0] || '';
  const allUrls = urls.length ? urls : firstUrl ? [firstUrl] : [];

  return allUrls.map((url, index) => ({
    url,
    type: mediaTypes[index] || (String(url).startsWith('cfstream:') ? 'video' : 'image'),
    width: dimensions[index]?.width || 0,
    height: dimensions[index]?.height || 0,
    ratio: dimensions[index]?.ratio || 0,
  }));
}

export async function mirrorPostToSupabase(post: any, fallbackPayload: any = {}) {
  const supabaseUserId = await currentSupabaseUserId();
  if (!supabaseUserId || !post?.id) return;

  const overlays = normalizeJsonArray(post.editor_overlays?.length ? post.editor_overlays : fallbackPayload.editor_overlays);
  const taggedUsers = normalizeJsonArray(post.tagged_users?.length ? post.tagged_users : fallbackPayload.tagged_users);
  const textOverlays = overlays.filter((item: any) => item?.type === 'text');
  const filterData = overlays.find((item: any) => item?.type === 'filter') || null;

  // Supabase stores relational post fields plus JSONB editor/media metadata for flexible NoSQL-style reads.
  await supabase.from('app_posts').upsert({
    legacy_post_id: cleanString(post.id, 120),
    user_id: supabaseUserId,
    app_user_id: cleanString(post.user_id || fallbackPayload.user_id, 120) || null,
    title: cleanString(post.title || fallbackPayload.title, 180) || null,
    content: cleanString(post.content ?? fallbackPayload.content, 4000),
    visibility: cleanString(post.visibility || fallbackPayload.visibility || 'public', 30),
    post_type: cleanString(post.post_type || fallbackPayload.post_type || 'general', 80),
    category: cleanString(post.category || fallbackPayload.category, 80) || null,
    location: cleanString(post.location || fallbackPayload.location, 180) || null,
    media: buildSupabaseMedia(post, fallbackPayload),
    media_dimensions: normalizeJsonArray(post.media_dimensions?.length ? post.media_dimensions : fallbackPayload.media_dimensions),
    editor_data: {
      filterData,
      textOverlays,
      overlays,
    },
    product_tags: [],
    tagged_users: taggedUsers,
    metadata: {
      audio: {
        provider: post.audio_provider || fallbackPayload.audio_provider || '',
        track_id: post.audio_track_id || fallbackPayload.audio_track_id || '',
        title: post.audio_title || fallbackPayload.audio_title || '',
        artist: post.audio_artist || fallbackPayload.audio_artist || '',
      },
      bridge: 'cloudflare_d1_to_supabase',
    },
    updated_at: new Date().toISOString(),
  }, { onConflict: 'legacy_post_id' });
}

export async function upsertSupabaseDocument(
  collection: string,
  documentKey: string,
  document: Record<string, unknown>,
  visibility: DocumentVisibility = 'private'
) {
  const supabaseUserId = await currentSupabaseUserId();
  const safeCollection = safeDocumentKey(collection);
  const safeKey = safeDocumentKey(documentKey);
  if (!supabaseUserId || !safeCollection || !safeKey) return null;

  // Supabase "NoSQL" data lives in Postgres JSONB. Keep private by default and rely on RLS.
  const { data, error } = await supabase
    .from('app_documents')
    .upsert({
      owner_id: supabaseUserId,
      collection: safeCollection,
      document_key: safeKey,
      visibility,
      document: document && typeof document === 'object' && !Array.isArray(document) ? document : {},
      updated_at: new Date().toISOString(),
    }, { onConflict: 'owner_id,collection,document_key' })
    .select()
    .maybeSingle();

  if (error) throw error;
  return data;
}

export async function listSupabaseDocuments(collection: string, limit = 50) {
  const safeCollection = safeDocumentKey(collection);
  if (!isSupabaseConfigured() || !safeCollection) return [];

  const { data, error } = await supabase
    .from('app_documents')
    .select('id, collection, document_key, visibility, document, created_at, updated_at')
    .eq('collection', safeCollection)
    .order('updated_at', { ascending: false })
    .limit(Math.max(1, Math.min(Number(limit) || 50, 100)));

  if (error) throw error;
  return data || [];
}
