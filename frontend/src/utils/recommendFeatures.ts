import api from '../api/client';

export type NotePost = {
  id: string;
  body: string;
  note_type: string;
  mood: string;
  color: string;
  media_url?: string;
  media_type?: string;
  anonymous: boolean;
  reactions_count: number;
  comments_count: number;
  saves_count: number;
  shares_count: number;
  reports_count?: number;
  reacted?: boolean;
  saved?: boolean;
  created_at?: string;
  user?: {
    id?: string;
    username?: string;
    full_name?: string;
    profile_image?: string;
  };
};

export type PeopleProfile = {
  id: string;
  owner_user_id?: string;
  name: string;
  role: string;
  category: string;
  bio: string;
  known_for: string;
  city: string;
  profile_image: string;
  instagram_url?: string;
  tiktok_url?: string;
  youtube_url?: string;
  website_url?: string;
  source_url?: string;
  claim_status?: string;
  followers_count: number;
  saves_count: number;
  reports_count?: number;
  followed?: boolean;
  saved?: boolean;
  similar_people?: PeopleProfile[];
};

export const NOTE_TYPES = [
  'thought',
  'feeling',
  'advice',
  'confession',
  'question',
  'quote',
  'memory',
  'mood',
  'journal',
];

export const NOTE_MOODS = [
  { id: 'soft', label: 'Soft', color: '#F6E7D7' },
  { id: 'calm', label: 'Calm', color: '#E7F1DF' },
  { id: 'blue', label: 'Blue', color: '#DCEAF8' },
  { id: 'love', label: 'Love', color: '#F8DDE7' },
  { id: 'night', label: 'Night', color: '#E7E1F5' },
  { id: 'gold', label: 'Gold', color: '#F7E7B7' },
  { id: 'green', label: 'Green', color: '#DFF0D8' },
  { id: 'gray', label: 'Gray', color: '#ECEBE6' },
];

export function compactNumber(value: number) {
  if (value >= 1000000) return `${(value / 1000000).toFixed(1).replace(/\.0$/, '')}M`;
  if (value >= 1000) return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}K`;
  return String(Math.max(0, Math.round(value || 0)));
}

export function normalizeNote(value: any): NotePost {
  return {
    id: String(value?.id || ''),
    body: String(value?.body || ''),
    note_type: String(value?.note_type || 'thought'),
    mood: String(value?.mood || 'soft'),
    color: String(value?.color || '#F6E7D7'),
    media_url: String(value?.media_url || ''),
    media_type: String(value?.media_type || ''),
    anonymous: !!value?.anonymous,
    reactions_count: Number(value?.reactions_count || 0),
    comments_count: Number(value?.comments_count || 0),
    saves_count: Number(value?.saves_count || 0),
    shares_count: Number(value?.shares_count || 0),
    reports_count: Number(value?.reports_count || 0),
    reacted: !!value?.reacted,
    saved: !!value?.saved,
    created_at: value?.created_at,
    user: value?.user || undefined,
  };
}

export function normalizePeople(value: any): PeopleProfile {
  return {
    id: String(value?.id || ''),
    owner_user_id: value?.owner_user_id ? String(value.owner_user_id) : undefined,
    name: String(value?.name || 'Creator'),
    role: String(value?.role || 'creator'),
    category: String(value?.category || 'creator'),
    bio: String(value?.bio || ''),
    known_for: String(value?.known_for || ''),
    city: String(value?.city || ''),
    profile_image: String(value?.profile_image || ''),
    instagram_url: String(value?.instagram_url || ''),
    tiktok_url: String(value?.tiktok_url || ''),
    youtube_url: String(value?.youtube_url || ''),
    website_url: String(value?.website_url || ''),
    source_url: String(value?.source_url || ''),
    claim_status: String(value?.claim_status || 'unclaimed'),
    followers_count: Number(value?.followers_count || 0),
    saves_count: Number(value?.saves_count || 0),
    reports_count: Number(value?.reports_count || 0),
    followed: !!value?.followed,
    saved: !!value?.saved,
    similar_people: Array.isArray(value?.similar_people) ? value.similar_people.map(normalizePeople) : [],
  };
}

export async function loadNotes(limit = 36) {
  const response = await api.get('/notes', { params: { limit } });
  return (Array.isArray(response.data) ? response.data : []).map(normalizeNote).filter((note: NotePost) => note.id);
}

export async function getNote(id: string) {
  const response = await api.get(`/notes/${encodeURIComponent(id)}`);
  return normalizeNote(response.data);
}

export async function createNote(payload: { body: string; note_type: string; mood: string; color?: string; anonymous?: boolean }) {
  const response = await api.post('/notes', payload);
  return normalizeNote(response.data);
}

export async function toggleNoteInteraction(id: string, kind: 'reaction' | 'save' | 'share', value?: string) {
  const response = await api.post(`/notes/${encodeURIComponent(id)}/interactions`, { kind, value });
  return { active: !!response.data?.active, kind: String(response.data?.kind || kind) };
}

export async function reportNote(id: string, reason = 'Note report') {
  await api.post(`/notes/${encodeURIComponent(id)}/report`, { reason });
}

export async function loadNoteComments(id: string) {
  const response = await api.get(`/notes/${encodeURIComponent(id)}/comments`);
  return Array.isArray(response.data) ? response.data : [];
}

export async function addNoteComment(id: string, body: string, parent_id = '') {
  const response = await api.post(`/notes/${encodeURIComponent(id)}/comments`, { body, parent_id });
  return response.data;
}

export async function loadPeople(limit = 36, q = '') {
  const response = await api.get('/people', { params: { limit, q } });
  return (Array.isArray(response.data) ? response.data : []).map(normalizePeople).filter((profile: PeopleProfile) => profile.id);
}

export async function getPeopleProfile(id: string) {
  const response = await api.get(`/people/${encodeURIComponent(id)}`);
  return normalizePeople(response.data);
}

export async function togglePeopleInteraction(id: string, kind: 'follow' | 'save') {
  const response = await api.post(`/people/${encodeURIComponent(id)}/interactions`, { kind });
  return { active: !!response.data?.active, kind: String(response.data?.kind || kind) };
}

export async function claimPeopleProfile(id: string, message: string, evidence_url = '') {
  const response = await api.post(`/people/${encodeURIComponent(id)}/claim`, { message, evidence_url });
  return response.data;
}

export async function reportPeopleProfile(id: string, reason = 'Wrong info') {
  await api.post(`/people/${encodeURIComponent(id)}/report`, { reason });
}
