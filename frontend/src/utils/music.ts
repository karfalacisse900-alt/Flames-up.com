import api from '../api/client';
import AsyncStorage from '@react-native-async-storage/async-storage';

export type AudiusTrack = {
  id: string;
  track_id: string;
  title: string;
  artist: string;
  artist_id?: string;
  artist_handle?: string;
  artist_profile_image?: string;
  artist_cover_image?: string;
  artist_location?: string;
  artist_followers?: number;
  artwork_url: string;
  duration: number;
  genre?: string;
  play_count?: number;
  favorite_count?: number;
  repost_count?: number;
  permalink?: string;
  description?: string;
  stream_url?: string;
};

export type SelectedPostSound = {
  audio_provider: 'audius';
  audio_track_id: string;
  audio_title: string;
  audio_artist: string;
  audio_artwork_url: string;
  audio_stream_url: string;
  audio_start_time: number;
  audio_duration: number;
};

const FAVORITE_SOUNDS_KEY = 'flames.favoriteAudiusSounds.v1';
const AUDIUS_PLAYLISTS_KEY = 'flames.audiusPlaylists.v1';

export type AudiusPlaylist = {
  id: string;
  name: string;
  tracks: AudiusTrack[];
  created_at: string;
  updated_at: string;
};

function normalizeTrack(track: any): AudiusTrack {
  return {
    id: String(track?.id || track?.track_id || ''),
    track_id: String(track?.track_id || track?.id || ''),
    title: String(track?.title || 'Untitled track'),
    artist: String(track?.artist || 'Audius artist'),
    artist_id: track?.artist_id ? String(track.artist_id) : undefined,
    artist_handle: track?.artist_handle ? String(track.artist_handle) : undefined,
    artist_profile_image: track?.artist_profile_image ? String(track.artist_profile_image) : undefined,
    artist_cover_image: track?.artist_cover_image ? String(track.artist_cover_image) : undefined,
    artist_location: track?.artist_location ? String(track.artist_location) : undefined,
    artist_followers: Number(track?.artist_followers || 0),
    artwork_url: String(track?.artwork_url || ''),
    duration: Number(track?.duration || 0),
    genre: track?.genre ? String(track.genre) : undefined,
    play_count: Number(track?.play_count || 0),
    favorite_count: Number(track?.favorite_count || 0),
    repost_count: Number(track?.repost_count || 0),
    permalink: track?.permalink ? String(track.permalink) : undefined,
    description: track?.description ? String(track.description) : undefined,
    stream_url: track?.stream_url ? String(track.stream_url) : undefined,
  };
}

function tracksFromResponse(data: any): AudiusTrack[] {
  const rows = Array.isArray(data?.tracks) ? data.tracks : Array.isArray(data) ? data : [];
  return rows.map(normalizeTrack).filter((track: AudiusTrack) => track.id);
}

export async function getAudiusTrendingTracks(limit = 50): Promise<AudiusTrack[]> {
  const response = await api.get('/music/audius/trending', { params: { time: 'week', limit } });
  return tracksFromResponse(response.data);
}

export async function searchAudiusTracks(query: string, limit = 50): Promise<AudiusTrack[]> {
  const q = query.trim();
  if (q.length < 2) return [];
  const response = await api.get('/music/audius/search', { params: { q, limit } });
  return tracksFromResponse(response.data);
}

export async function getAudiusTrackStream(trackId: string): Promise<AudiusTrack> {
  const response = await api.get(`/music/audius/stream/${encodeURIComponent(trackId)}`);
  return normalizeTrack(response.data);
}

async function getLocalFavoriteAudiusTracks(): Promise<AudiusTrack[]> {
  try {
    const raw = await AsyncStorage.getItem(FAVORITE_SOUNDS_KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    return Array.isArray(parsed) ? parsed.map(normalizeTrack).filter((track) => track.id) : [];
  } catch {
    return [];
  }
}

async function saveLocalFavoriteAudiusTracks(tracks: AudiusTrack[]) {
  const unique = new Map<string, AudiusTrack>();
  tracks.forEach((track) => {
    const normalized = normalizeTrack(track);
    if (normalized.id) unique.set(normalized.id, normalized);
  });
  await AsyncStorage.setItem(FAVORITE_SOUNDS_KEY, JSON.stringify([...unique.values()].slice(0, 100)));
}

export async function getFavoriteAudiusTracks(): Promise<AudiusTrack[]> {
  try {
    const response = await api.get('/music/audius/favorites');
    const tracks = tracksFromResponse(response.data);
    await saveLocalFavoriteAudiusTracks(tracks);
    return tracks;
  } catch {
    return getLocalFavoriteAudiusTracks();
  }
}

export async function toggleFavoriteAudiusTrack(track: AudiusTrack): Promise<{ favorites: AudiusTrack[]; isFavorite: boolean }> {
  const normalized = normalizeTrack(track);
  const current = await getFavoriteAudiusTracks();
  const exists = current.some((item) => item.id === normalized.id);
  const favorites = exists
    ? current.filter((item) => item.id !== normalized.id)
    : [normalized, ...current].slice(0, 100);

  try {
    if (exists) {
      await api.delete(`/music/audius/favorites/${encodeURIComponent(normalized.id)}`);
    } else {
      await api.post('/music/audius/favorites', normalized);
    }
  } catch {
    // Keep the UI useful offline; the next successful load will sync back to the server state.
  }

  await saveLocalFavoriteAudiusTracks(favorites);
  return { favorites, isFavorite: !exists };
}

export async function getAudiusPlaylists(): Promise<AudiusPlaylist[]> {
  try {
    const raw = await AsyncStorage.getItem(AUDIUS_PLAYLISTS_KEY);
    const parsed = raw ? JSON.parse(raw) : [];
    if (!Array.isArray(parsed)) return [];
    return parsed.map((playlist: any) => ({
      id: String(playlist?.id || `playlist_${Date.now()}`),
      name: String(playlist?.name || 'My playlist'),
      tracks: Array.isArray(playlist?.tracks) ? playlist.tracks.map(normalizeTrack).filter((track: AudiusTrack) => track.id) : [],
      created_at: String(playlist?.created_at || new Date().toISOString()),
      updated_at: String(playlist?.updated_at || playlist?.created_at || new Date().toISOString()),
    }));
  } catch {
    return [];
  }
}

export async function createAudiusPlaylist(name: string, tracks: AudiusTrack[] = []): Promise<AudiusPlaylist[]> {
  const now = new Date().toISOString();
  const cleanName = name.replace(/\s+/g, ' ').trim().slice(0, 42) || 'My playlist';
  const current = await getAudiusPlaylists();
  const playlist: AudiusPlaylist = {
    id: `playlist_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    name: cleanName,
    tracks: tracks.map(normalizeTrack).filter((track) => track.id).slice(0, 100),
    created_at: now,
    updated_at: now,
  };
  const next = [playlist, ...current].slice(0, 40);
  await AsyncStorage.setItem(AUDIUS_PLAYLISTS_KEY, JSON.stringify(next));
  return next;
}

export function soundFromPost(post: any): SelectedPostSound | null {
  if (post?.audio_provider !== 'audius' || !post?.audio_track_id) return null;
  return {
    audio_provider: 'audius',
    audio_track_id: String(post.audio_track_id),
    audio_title: String(post.audio_title || 'Original sound'),
    audio_artist: String(post.audio_artist || 'Audius artist'),
    audio_artwork_url: String(post.audio_artwork_url || ''),
    audio_stream_url: String(post.audio_stream_url || ''),
    audio_start_time: Number(post.audio_start_time || 0),
    audio_duration: Number(post.audio_duration || 15),
  };
}
