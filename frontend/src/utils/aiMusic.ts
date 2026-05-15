import api from '../api/client';

export type AiMusicPost = {
  id: string;
  user_id?: string;
  provider: 'elevenlabs';
  prompt_text: string;
  lyrics_text: string;
  mood: string;
  style: string;
  audio_url: string;
  audio_duration: number;
  waveform_data: number[];
  status: 'pending' | 'generated' | 'failed' | 'removed';
  is_public: boolean;
  likes_count: number;
  comments_count: number;
  saves_count: number;
  reposts_count: number;
  reports_count?: number;
  liked?: boolean;
  saved?: boolean;
  reposted?: boolean;
  created_at?: string;
  updated_at?: string;
  user?: {
    id?: string;
    username?: string;
    full_name?: string;
    profile_image?: string;
  };
};

export const MUSIC_MOODS = [
  'chill',
  'sad',
  'love',
  'hype',
  'dreamy',
  'motivational',
  'late night',
  'soft',
  'cinematic',
  'spiritual',
  'afro vibe',
  'rap vibe',
];

export const MUSIC_STYLES = [
  'spoken word',
  'singing',
  'rap',
  'ambient',
  'melodic',
  'soft female voice',
  'soft male voice',
  'ambient voice',
];

export function normalizeAiMusicPost(value: any): AiMusicPost {
  const waveform = Array.isArray(value?.waveform_data)
    ? value.waveform_data
    : [];
  return {
    id: String(value?.id || ''),
    user_id: value?.user_id ? String(value.user_id) : undefined,
    provider: 'elevenlabs',
    prompt_text: String(value?.prompt_text || ''),
    lyrics_text: String(value?.lyrics_text || value?.prompt_text || ''),
    mood: String(value?.mood || 'chill'),
    style: String(value?.style || 'spoken word'),
    audio_url: String(value?.audio_url || ''),
    audio_duration: Number(value?.audio_duration || 20),
    waveform_data: waveform.map((item: unknown) => Number(item || 0.3)).filter(Number.isFinite),
    status: value?.status || 'pending',
    is_public: !!value?.is_public,
    likes_count: Number(value?.likes_count || 0),
    comments_count: Number(value?.comments_count || 0),
    saves_count: Number(value?.saves_count || 0),
    reposts_count: Number(value?.reposts_count || 0),
    reports_count: Number(value?.reports_count || 0),
    liked: !!value?.liked,
    saved: !!value?.saved,
    reposted: !!value?.reposted,
    created_at: value?.created_at,
    updated_at: value?.updated_at,
    user: value?.user || undefined,
  };
}

export async function loadAiMusicFeed(limit = 30): Promise<AiMusicPost[]> {
  const response = await api.get('/music/feed', { params: { limit } });
  const rows = Array.isArray(response.data?.posts) ? response.data.posts : Array.isArray(response.data) ? response.data : [];
  return rows.map(normalizeAiMusicPost).filter((post: AiMusicPost) => post.id);
}

export async function generateAiMusicPost(payload: { prompt_text: string; mood: string; style: string }): Promise<AiMusicPost> {
  const response = await api.post('/music/generate', payload);
  return normalizeAiMusicPost(response.data?.post || response.data);
}

export async function getAiMusicPost(id: string): Promise<AiMusicPost> {
  const response = await api.get(`/music/${encodeURIComponent(id)}`);
  return normalizeAiMusicPost(response.data?.post || response.data);
}

export async function publishAiMusicPost(id: string) {
  await api.post(`/music/${encodeURIComponent(id)}/publish`);
}

export async function reportAiMusicPost(id: string, reason = 'AI music report') {
  await api.post(`/music/${encodeURIComponent(id)}/report`, { reason });
}

export async function toggleAiMusicInteraction(id: string, kind: 'like' | 'save' | 'repost' | 'use_sound') {
  const response = await api.post(`/music/${encodeURIComponent(id)}/interactions`, { kind });
  return {
    active: !!response.data?.active,
    kind: String(response.data?.kind || kind),
  };
}
