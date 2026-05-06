import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, ActivityIndicator, Alert, TextInput,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { Audio } from 'expo-av';
import api from '../../src/api/client';
import { useAuthStore } from '../../src/store/authStore';
import { colors } from '../../src/utils/theme';
import { useI18n } from '../../src/utils/i18n';
import { requireVerifiedPhone } from '../../src/utils/phoneVerification';
import NoteCard from '../../src/components/NoteCard';
import {
  AudiusTrack,
  getAudiusTrackStream,
  getAudiusTrendingTracks,
  getFavoriteAudiusTracks,
  searchAudiusTracks,
  toggleFavoriteAudiusTrack,
} from '../../src/utils/music';
import {
  NotePost,
  loadNotes,
} from '../../src/utils/recommendFeatures';

const CITY_TABS = [
  { id: 'all', label: 'For You' },
  { id: 'notes', label: 'Notes' },
  { id: 'music', label: 'Music' },
];

const RECOMMEND_CATEGORIES = [
  { id: 'notes', label: 'Notes' },
  { id: 'music', label: 'Music' },
];

const RECOMMEND_PAGE_IDS = new Set(RECOMMEND_CATEGORIES.map((category) => category.id));

type Recommendation = {
  id: string;
  title: string;
  description?: string;
  category?: string;
  tags?: string[];
  external_url?: string;
  provider?: string;
  embed_url?: string;
  thumbnail_url?: string;
  creator_name?: string;
  user?: {
    username?: string;
    full_name?: string;
    profile_image?: string;
  };
};

function formatDuration(seconds: unknown) {
  const total = Math.max(0, Math.round(Number(seconds || 0)));
  const minutes = Math.floor(total / 60);
  const rest = `${total % 60}`.padStart(2, '0');
  return `${minutes}:${rest}`;
}

function recommendationCardColor(item: Recommendation, index: number) {
  if (item.thumbnail_url) return '#F3F4F0';
  const palette = ['#C9E7F8', '#C7353E', '#D8C0A8', '#E6D9BF', '#BFD8C2', '#F4D4C8', '#E9E8E1'];
  return palette[index % palette.length];
}

function recommendationProviderLabel(item: Recommendation) {
  const provider = String(item.provider || item.category || 'link').replace(/_/g, ' ');
  return provider.charAt(0).toUpperCase() + provider.slice(1);
}

function recommendationAuthor(item: Recommendation) {
  return item.creator_name || item.user?.full_name || item.user?.username || 'Community pick';
}

export default function DiscoverScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const { t } = useI18n();
  const [tab, setTab] = useState('all');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [statusGroups, setStatusGroups] = useState<any[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [recommendCategory, setRecommendCategory] = useState('music');
  const [recommendLoading, setRecommendLoading] = useState(false);
  const [audiusTracks, setAudiusTracks] = useState<AudiusTrack[]>([]);
  const [audiusFavorites, setAudiusFavorites] = useState<AudiusTrack[]>([]);
  const [audiusQuery, setAudiusQuery] = useState('');
  const [audiusLoading, setAudiusLoading] = useState(false);
  const [audiusPlayingId, setAudiusPlayingId] = useState('');
  const [audiusLoadingId, setAudiusLoadingId] = useState('');
  const [notes, setNotes] = useState<NotePost[]>([]);
  const [notesLoading, setNotesLoading] = useState(false);
  const audiusSoundRef = useRef<Audio.Sound | null>(null);
  const audiusQueryRef = useRef('');

  const loadStatusGroups = useCallback(async () => {
    try {
      const r = await api.get('/statuses');
      const groups = Array.isArray(r.data) ? r.data : [];
      setStatusGroups(groups.filter((group: any) => (
        group?.user_id
        && group.user_id !== user?.id
        && Array.isArray(group.statuses)
        && group.statuses.length > 0
      )));
    } catch (error: any) {
      console.log('Could not load public stories', error?.response?.data?.detail || error?.message);
      setStatusGroups([]);
    }
  }, [user?.id]);

  const loadRecommendations = useCallback(async (category = 'all') => {
    setRecommendLoading(true);
    try {
      const r = await api.get('/recommendations', {
        params: {
          category,
          limit: 48,
        },
      });
      setRecommendations(Array.isArray(r.data) ? r.data : []);
    } catch (error: any) {
      console.log('Could not load recommendations', error?.response?.data?.detail || error?.message);
      setRecommendations([]);
    } finally {
      setRecommendLoading(false);
    }
  }, []);

  const loadAudiusDiscovery = useCallback(async (queryOverride?: string) => {
    setAudiusLoading(true);
    try {
      const query = (queryOverride ?? audiusQueryRef.current).trim();
      const [tracks, favorites] = await Promise.all([
        query.length >= 2 ? searchAudiusTracks(query, 50) : getAudiusTrendingTracks(50),
        getFavoriteAudiusTracks().catch(() => []),
      ]);
      setAudiusTracks(tracks);
      setAudiusFavorites(favorites);
    } catch (error: any) {
      console.log('Could not load Audius music', error?.response?.data?.detail || error?.message);
      setAudiusTracks([]);
    } finally {
      setAudiusLoading(false);
    }
  }, []);

  const loadNotePosts = useCallback(async () => {
    setNotesLoading(true);
    try {
      setNotes(await loadNotes(36));
    } catch (error: any) {
      console.log('Could not load notes', error?.response?.data?.detail || error?.message);
      setNotes([]);
    } finally {
      setNotesLoading(false);
    }
  }, []);

  const stopAudiusPreview = useCallback(async () => {
    const sound = audiusSoundRef.current;
    audiusSoundRef.current = null;
    setAudiusPlayingId('');
    setAudiusLoadingId('');
    if (sound) {
      await sound.stopAsync().catch(() => undefined);
      await sound.unloadAsync().catch(() => undefined);
    }
  }, []);

  useEffect(() => () => {
    void stopAudiusPreview();
  }, [stopAudiusPreview]);

  const playAudiusTrack = useCallback(async (track: AudiusTrack) => {
    const trackId = track.track_id || track.id;
    if (!trackId) return;
    if (audiusPlayingId === trackId) {
      await stopAudiusPreview();
      return;
    }
    setAudiusLoadingId(trackId);
    try {
      await stopAudiusPreview();
      const streamTrack = track.stream_url ? track : await getAudiusTrackStream(trackId);
      if (!streamTrack.stream_url) {
        Alert.alert('Audio unavailable', 'Audius did not return a stream for this track.');
        return;
      }
      await Audio.setAudioModeAsync({ playsInSilentModeIOS: true }).catch(() => undefined);
      const { sound } = await Audio.Sound.createAsync(
        { uri: streamTrack.stream_url },
        { shouldPlay: true, volume: 1 }
      );
      sound.setOnPlaybackStatusUpdate((status: any) => {
        if (status?.didJustFinish) void stopAudiusPreview();
      });
      audiusSoundRef.current = sound;
      setAudiusPlayingId(trackId);
    } catch (error: any) {
      Alert.alert('Playback failed', error?.response?.data?.detail || error?.message || 'Could not play this Audius track.');
    } finally {
      setAudiusLoadingId('');
    }
  }, [audiusPlayingId, stopAudiusPreview]);

  const toggleAudiusFavorite = useCallback(async (track: AudiusTrack) => {
    try {
      const result = await toggleFavoriteAudiusTrack(track);
      setAudiusFavorites(result.favorites);
    } catch (error: any) {
      Alert.alert('Could not save sound', error?.response?.data?.detail || 'Try again in a moment.');
    }
  }, []);

  const handleUseAudiusSound = useCallback(async (track: AudiusTrack) => {
    try {
      const trackId = track.track_id || track.id;
      const streamTrack = track.stream_url ? track : await getAudiusTrackStream(trackId);
      router.push({
        pathname: '/create-post',
        params: {
          audio_provider: 'audius',
          audio_track_id: streamTrack.track_id || streamTrack.id,
          audio_title: streamTrack.title,
          audio_artist: streamTrack.artist,
          audio_artwork_url: streamTrack.artwork_url,
          audio_stream_url: streamTrack.stream_url || '',
          audio_start_time: '0',
          audio_duration: '15',
        },
      } as any);
    } catch (error: any) {
      Alert.alert('Could not use sound', error?.response?.data?.detail || 'Try another Audius track.');
    }
  }, [router]);

  useEffect(() => {
    let mounted = true;
    async function bootstrap() {
      setLoading(true);
      await Promise.all([loadStatusGroups(), loadAudiusDiscovery()]);
      if (mounted) setLoading(false);
    }
    bootstrap();
    return () => { mounted = false; };
  }, [loadStatusGroups, loadAudiusDiscovery]);

  useEffect(() => {
    const activeCategory = RECOMMEND_PAGE_IDS.has(tab) ? tab : recommendCategory;
    if (!RECOMMEND_PAGE_IDS.has(activeCategory)) return;
    if (activeCategory === 'music') {
      loadAudiusDiscovery();
    } else if (activeCategory === 'notes') {
      loadNotePosts();
    } else {
      loadRecommendations(activeCategory);
    }
  }, [loadAudiusDiscovery, loadNotePosts, loadRecommendations, recommendCategory, tab]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true);
    const activeCategory = RECOMMEND_PAGE_IDS.has(tab) ? tab : recommendCategory;
    await Promise.all([
      loadStatusGroups(),
      activeCategory === 'music'
        ? loadAudiusDiscovery()
        : activeCategory === 'notes'
          ? loadNotePosts()
          : RECOMMEND_PAGE_IDS.has(activeCategory)
            ? loadRecommendations(activeCategory)
            : Promise.resolve(),
    ]);
    setRefreshing(false);
  }, [loadAudiusDiscovery, loadNotePosts, loadRecommendations, loadStatusGroups, recommendCategory, tab]);

  const renderRecommendationCard = (item: Recommendation, index: number) => {
    const tall = index % 5 === 0 || index % 5 === 3;
    const bg = recommendationCardColor(item, index);
    return (
      <TouchableOpacity
        key={item.id}
        style={[s.recommendCard, { minHeight: tall ? 228 : 184, backgroundColor: bg }]}
        activeOpacity={0.88}
        onPress={() => router.push(`/recommendation/${item.id}` as any)}
      >
        {item.thumbnail_url ? (
          <Image source={{ uri: item.thumbnail_url }} style={s.recommendCardImage} resizeMode="cover" />
        ) : null}
        <View style={[s.recommendCardShade, item.thumbnail_url ? s.recommendCardShadeOnImage : null]} />
        <View style={s.recommendCardCopy}>
          <Text style={[s.recommendSmall, item.thumbnail_url && s.recommendTextOnImage]} numberOfLines={1}>
            {recommendationProviderLabel(item)}
          </Text>
          <Text style={[s.recommendCardTitle, item.thumbnail_url && s.recommendTextOnImage]} numberOfLines={3}>
            {item.title}
          </Text>
          <Text style={[s.recommendCardMeta, item.thumbnail_url && s.recommendTextOnImage]} numberOfLines={1}>
            {recommendationAuthor(item)}
          </Text>
        </View>
        <View style={s.recommendReadMore}>
          <Text style={[s.recommendReadText, item.thumbnail_url && s.recommendReadTextOnImage]}>READ MORE</Text>
          <Ionicons name="arrow-forward" size={12} color={item.thumbnail_url ? '#FFFFFF' : '#111111'} />
        </View>
      </TouchableOpacity>
    );
  };

  const renderAudiusTrackCard = (track: AudiusTrack, index: number) => {
    const trackId = track.track_id || track.id;
    const favorite = audiusFavorites.some((item) => (item.track_id || item.id) === trackId);
    const playing = audiusPlayingId === trackId;
    const loadingTrack = audiusLoadingId === trackId;
    return (
      <TouchableOpacity
        key={trackId || `${track.title}-${index}`}
        style={s.audiusCard}
        activeOpacity={0.9}
        onPress={() => router.push({
          pathname: '/music/[id]',
          params: {
            id: trackId,
            title: track.title,
            artist: track.artist,
            artwork: track.artwork_url,
            duration: String(track.duration || 0),
          },
        } as any)}
      >
        <View style={s.audiusArtworkWrap}>
          {track.artwork_url ? (
            <Image source={{ uri: track.artwork_url }} style={s.audiusArtwork} resizeMode="cover" />
          ) : (
            <View style={s.audiusArtworkFallback}>
              <Ionicons name="musical-notes-outline" size={34} color="#111111" />
            </View>
          )}
          <TouchableOpacity style={s.audiusPlayButton} onPress={() => playAudiusTrack(track)} activeOpacity={0.86}>
            {loadingTrack ? (
              <ActivityIndicator size="small" color="#111111" />
            ) : (
              <Ionicons name={playing ? 'pause' : 'play'} size={18} color="#111111" />
            )}
          </TouchableOpacity>
        </View>
        <View style={s.audiusCopy}>
          <View style={s.audiusMetaRow}>
            <Text style={s.audiusSource}>AUDIUS</Text>
            <Text style={s.audiusDot}>•</Text>
            <Text style={s.audiusDuration}>{formatDuration(track.duration)}</Text>
          </View>
          <Text style={s.audiusTitle} numberOfLines={2}>{track.title}</Text>
          <Text style={s.audiusArtist} numberOfLines={1}>{track.artist}</Text>
          <View style={s.audiusActions}>
            <TouchableOpacity style={s.audiusPrimaryAction} onPress={() => handleUseAudiusSound(track)} activeOpacity={0.86}>
              <Ionicons name="add-circle-outline" size={16} color="#111111" />
              <Text style={s.audiusPrimaryActionText}>Use sound</Text>
            </TouchableOpacity>
            <TouchableOpacity style={[s.audiusIconAction, favorite && s.audiusIconActionOn]} onPress={() => toggleAudiusFavorite(track)} activeOpacity={0.82}>
              <Ionicons name={favorite ? 'bookmark' : 'bookmark-outline'} size={17} color="#111111" />
            </TouchableOpacity>
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  const renderRecommendTab = () => {
    const activeCategory = RECOMMEND_PAGE_IDS.has(tab) ? tab : recommendCategory;
    const directPage = RECOMMEND_PAGE_IDS.has(tab);
    const left = recommendations.filter((_, index) => index % 2 === 0);
    const right = recommendations.filter((_, index) => index % 2 === 1);
    const isMusicPage = activeCategory === 'music';
    const isNotesPage = activeCategory === 'notes';
    const showCreate = isNotesPage;
    const createRoute = isNotesPage ? '/create-note' : '/create-recommendation';
    const brandIcon = isMusicPage ? 'radio-outline' : isNotesPage ? 'moon-outline' : 'albums-outline';
    const brandText = isMusicPage ? 'AUDIUS DISCOVERY' : isNotesPage ? 'NOTES' : 'FLAMES RECS';

    return (
      <View style={s.recommendRoot}>
        <View style={s.recommendTopBar}>
          <View style={s.recommendBrandPill}>
            <Ionicons name={brandIcon as any} size={17} color="#111111" />
            <Text style={s.recommendBrandText}>{brandText}</Text>
          </View>
          {showCreate ? (
            <TouchableOpacity style={s.recommendMenuBtn} onPress={() => router.push(createRoute as any)}>
              <Ionicons name="add" size={24} color="#111111" />
            </TouchableOpacity>
          ) : <View style={s.recommendMenuSpacer} />}
        </View>

        {!directPage ? (
          <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.recommendCategoryRail}>
            {RECOMMEND_CATEGORIES.map((category, index) => {
              const active = category.id === activeCategory;
              return (
                <TouchableOpacity
                  key={category.id}
                  style={[
                    s.recommendCategoryPill,
                    { backgroundColor: ['#E7CFB7', '#D87A86', '#D7EFF7', '#DDF0CA', '#F2DFBE', '#E8E2F3', '#F6D3C9'][index % 7] },
                    active && s.recommendCategoryPillOn,
                  ]}
                  onPress={() => setRecommendCategory(category.id)}
                >
                  <Text style={[s.recommendCategoryText, active && s.recommendCategoryTextOn]}>{category.label}</Text>
                </TouchableOpacity>
              );
            })}
          </ScrollView>
        ) : null}

        {(!isMusicPage && !isNotesPage) ? (
          <TouchableOpacity style={s.submitRecommendButton} activeOpacity={0.85} onPress={() => router.push('/create-recommendation' as any)}>
            <View>
              <Text style={s.submitRecommendTitle}>Submit recommend</Text>
              <Text style={s.submitRecommendSub}>Share a note, music find, video, podcast, or link.</Text>
            </View>
            <Ionicons name="chevron-forward" size={22} color="#111111" />
          </TouchableOpacity>
        ) : null}

        {isMusicPage ? (
          <>
            <View style={s.audiusHero}>
              <Text style={s.audiusHeroTitle}>Underground sounds</Text>
              <Text style={s.audiusHeroText}>Discover independent artists and tracks from Audius. Search a sound, preview it, save it, or use it in a post.</Text>
              <View style={s.audiusSearchBox}>
                <Ionicons name="search" size={18} color="#777777" />
                <TextInput
                  value={audiusQuery}
                  onChangeText={(text) => {
                    audiusQueryRef.current = text;
                    setAudiusQuery(text);
                  }}
                  onSubmitEditing={() => loadAudiusDiscovery()}
                  placeholder="Search artists, songs, underground..."
                  placeholderTextColor="#8A8A8A"
                  style={s.audiusSearchInput}
                  returnKeyType="search"
                />
                {audiusQuery.trim() ? (
                  <TouchableOpacity
                    onPress={() => {
                      audiusQueryRef.current = '';
                      setAudiusQuery('');
                      loadAudiusDiscovery('');
                    }}
                    style={s.audiusSearchClear}
                  >
                    <Ionicons name="close" size={16} color="#111111" />
                  </TouchableOpacity>
                ) : null}
              </View>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.audiusChipRail}>
                {['underground', 'indie', 'lofi', 'afrobeats', 'jersey club', 'bedroom pop'].map((query) => (
                  <TouchableOpacity
                    key={query}
                    style={s.audiusChip}
                    onPress={() => {
                      audiusQueryRef.current = query;
                      setAudiusQuery(query);
                      loadAudiusDiscovery(query);
                    }}
                  >
                    <Text style={s.audiusChipText}>{query}</Text>
                  </TouchableOpacity>
                ))}
              </ScrollView>
            </View>
            {audiusLoading && audiusTracks.length === 0 ? (
              <View style={s.recommendLoading}>
                <ActivityIndicator color="#111111" />
              </View>
            ) : audiusTracks.length > 0 ? (
              <View style={s.audiusList}>
                {audiusTracks.map(renderAudiusTrackCard)}
              </View>
            ) : (
              <View style={s.recommendEmpty}>
                <Ionicons name="radio-outline" size={34} color="#888888" />
                <Text style={s.recommendEmptyTitle}>No Audius tracks found</Text>
                <Text style={s.recommendEmptyText}>Try another artist, genre, or underground sound keyword.</Text>
              </View>
            )}
          </>
        ) : isNotesPage ? (
          notesLoading && notes.length === 0 ? (
            <View style={s.recommendLoading}><ActivityIndicator color="#111111" /></View>
          ) : notes.length > 0 ? (
            <View style={s.noteList}>
              {notes.map((note) => (
                <NoteCard
                  key={note.id}
                  note={note}
                  onChanged={(next) => setNotes((current) => current.map((item) => item.id === next.id ? next : item))}
                />
              ))}
            </View>
          ) : (
            <View style={s.recommendEmpty}>
              <Ionicons name="moon-outline" size={34} color="#888888" />
              <Text style={s.recommendEmptyTitle}>No notes yet</Text>
              <Text style={s.recommendEmptyText}>Share a thought, confession, question, mood, or mini journal post.</Text>
              <TouchableOpacity style={s.recommendEmptyButton} onPress={() => router.push('/create-note' as any)}>
                <Text style={s.recommendEmptyButtonText}>Write note</Text>
              </TouchableOpacity>
            </View>
          )
        ) : recommendLoading && recommendations.length === 0 ? (
          <View style={s.recommendLoading}>
            <ActivityIndicator color="#111111" />
          </View>
        ) : recommendations.length > 0 ? (
          <View style={s.recommendGrid}>
            <View style={s.recommendColumn}>
              {left.map((item, index) => renderRecommendationCard(item, index * 2))}
            </View>
            <View style={s.recommendColumn}>
              {right.map((item, index) => renderRecommendationCard(item, index * 2 + 1))}
            </View>
          </View>
        ) : (
          <View style={s.recommendEmpty}>
            <Ionicons name="sparkles-outline" size={34} color="#888888" />
            <Text style={s.recommendEmptyTitle}>No recommendations yet</Text>
            <Text style={s.recommendEmptyText}>Be the first to share something worth watching, reading, or listening to.</Text>
            <TouchableOpacity style={s.recommendEmptyButton} onPress={() => router.push('/create-recommendation' as any)}>
              <Text style={s.recommendEmptyButtonText}>Add one</Text>
            </TouchableOpacity>
          </View>
        )}
      </View>
    );
  };

  return (
    <View style={s.root}>
      {/* Header */}
      <View style={[s.header, { paddingTop: insets.top + 4 }]}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.tabs}>
          {CITY_TABS.map(c => (
            <TouchableOpacity key={c.id} onPress={() => setTab(c.id)}>
              <Text style={[s.tabTx, tab === c.id && s.tabTxOn]}>{c.label.toUpperCase()}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
        <TouchableOpacity style={s.searchIcon}><Ionicons name="search" size={18} color="#1A1A1A" /></TouchableOpacity>
      </View>

      <ScrollView
        showsVerticalScrollIndicator={false}
        refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor="#1A1A1A" />}
        contentContainerStyle={{ paddingBottom: 100 }}
      >
        {loading ? (
          <View style={s.center}><ActivityIndicator size="large" color="#1A1A1A" /></View>
        ) : RECOMMEND_PAGE_IDS.has(tab) ? (
          renderRecommendTab()
        ) : (
          <>
            {/* Search */}
            <View style={s.searchWrap}>
              <View style={s.searchBar}>
                <Ionicons name="search" size={18} color="#999" />
                <Text style={s.searchPh}>{t('searchPrompt')}</Text>
              </View>
            </View>

            {/* Story statuses */}
            <View style={s.peopleSection}>
              <Text style={s.peopleSectionTitle}>Stories</Text>
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={s.peopleScroll}>
                <TouchableOpacity
                  key="your-story"
                  style={s.personCard}
                  activeOpacity={0.9}
                  onPress={() => {
                    if (!requireVerifiedPhone(user, router, 'share stories')) return;
                    router.push('/create-status' as any);
                  }}
                >
                  <View style={s.yourStoryImageWrap}>
                    {user?.profile_image ? (
                      <Image source={{ uri: user.profile_image }} style={s.personImg} />
                    ) : (
                      <View style={[s.personImg, s.yourStoryFallback]}>
                        <Text style={s.yourStoryInitial}>
                          {(user?.full_name || user?.username || 'Y')[0].toUpperCase()}
                        </Text>
                      </View>
                    )}
                    <View style={s.yourStoryPlus}>
                      <Ionicons name="add" size={16} color="#FFF" />
                    </View>
                  </View>
                  <Text style={s.personName} numberOfLines={1}>{t('yourStory')}</Text>
                  <Text style={s.personBio} numberOfLines={1}>{user?.username || user?.full_name || ''}</Text>
                </TouchableOpacity>
                  {statusGroups.map((group: any) => (
                    <TouchableOpacity
                      key={group.user_id}
                      style={s.personCard}
                      activeOpacity={0.9}
                      onPress={() => router.push({ pathname: '/story-viewer', params: { userId: group.user_id } } as any)}
                    >
                      <View style={[s.statusRing, group.has_unviewed && s.statusRingActive]}>
                        {group.user_profile_image ? (
                          <Image source={{ uri: group.user_profile_image }} style={s.personImg} />
                        ) : (
                          <View style={[s.personImg, { backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' }]}>
                            <Text style={s.personInit}>{(group.user_full_name || group.user_username || 'U')[0]}</Text>
                          </View>
                        )}
                      </View>
                      <Text style={s.personName} numberOfLines={1}>{group.user_full_name || group.user_username || 'Story'}</Text>
                      <Text style={s.personBio} numberOfLines={1}>
                        {group.statuses?.length || 1} update{group.statuses?.length === 1 ? '' : 's'}
                      </Text>
                    </TouchableOpacity>
                  ))}
                  {statusGroups.length === 0 ? (
                    <View style={s.emptyStoryCard}>
                      <Ionicons name="sparkles-outline" size={22} color="#9B9B9B" />
                      <Text style={s.emptyStoryText}>Public stories will appear here.</Text>
                    </View>
                  ) : null}
              </ScrollView>
            </View>

          </>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.white },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingBottom: 10, gap: 12 },
  tabs: { gap: 20, alignItems: 'center' },
  tabTx: { fontSize: 13, fontWeight: '600', color: '#BBB', letterSpacing: 0.5 },
  tabTxOn: { color: '#1A1A1A', fontWeight: '800', textDecorationLine: 'underline' },
  searchIcon: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' },

  searchWrap: { paddingHorizontal: 16, paddingBottom: 16 },
  searchBar: { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: '#F5F5F5', borderRadius: 24, paddingHorizontal: 16, paddingVertical: 12 },
  searchPh: { fontSize: 14, color: '#AAA' },

  peopleSection: { paddingLeft: 16, marginBottom: 20 },
  peopleSectionTitle: { fontSize: 18, fontWeight: '800', color: '#1A1A1A', marginBottom: 12 },
  peopleScroll: { gap: 12, paddingRight: 16 },
  personCard: { width: 130, alignItems: 'center' },
  personImg: { width: 100, height: 100, borderRadius: 50 },
  personInit: { fontSize: 28, fontWeight: '800', color: '#CCC' },
  personName: { fontSize: 14, fontWeight: '700', color: '#1A1A1A', marginTop: 8, textAlign: 'center' },
  personBio: { fontSize: 11, color: '#999', textAlign: 'center', marginTop: 2 },
  statusRing: { width: 106, height: 106, borderRadius: 53, justifyContent: 'center', alignItems: 'center', borderWidth: 2, borderColor: '#E6E6E6' },
  statusRingActive: { borderColor: colors.accentPrimary },
  yourStoryImageWrap: { width: 100, height: 100, position: 'relative' },
  yourStoryFallback: { backgroundColor: '#F5F2EC', borderWidth: 2, borderColor: '#DDD8CC', justifyContent: 'center', alignItems: 'center' },
  yourStoryInitial: { fontSize: 30, fontWeight: '900', color: colors.accentPrimary },
  yourStoryPlus: {
    position: 'absolute',
    right: 4,
    bottom: 4,
    width: 26,
    height: 26,
    borderRadius: 13,
    backgroundColor: colors.accentPrimary,
    borderWidth: 2,
    borderColor: colors.white,
    justifyContent: 'center',
    alignItems: 'center',
  },
  emptyStoryCard: {
    width: 178,
    height: 124,
    borderRadius: 18,
    backgroundColor: '#F5F5F5',
    borderWidth: 1,
    borderColor: '#ECECEC',
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 14,
  },
  emptyStoryText: { marginTop: 8, fontSize: 12, lineHeight: 16, color: '#777', textAlign: 'center', fontWeight: '700' },

  recommendRoot: { paddingHorizontal: 14, paddingTop: 6, paddingBottom: 36 },
  recommendTopBar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingBottom: 18 },
  recommendBrandPill: { minHeight: 36, borderRadius: 18, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#ECECEC', flexDirection: 'row', alignItems: 'center', gap: 7, paddingHorizontal: 13 },
  recommendBrandText: { color: '#111111', fontSize: 12, fontWeight: '900', letterSpacing: 0.2 },
  recommendMenuBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#ECECEC', alignItems: 'center', justifyContent: 'center' },
  recommendMenuSpacer: { width: 42, height: 42 },
  recommendCategoryRail: { gap: 8, paddingBottom: 14 },
  recommendCategoryPill: { minHeight: 34, borderRadius: 17, justifyContent: 'center', paddingHorizontal: 12 },
  recommendCategoryPillOn: { borderWidth: 1.3, borderColor: '#111111' },
  recommendCategoryText: { color: '#333333', fontSize: 12, fontWeight: '700' },
  recommendCategoryTextOn: { color: '#111111', fontWeight: '900' },
  submitRecommendButton: { minHeight: 68, borderRadius: 18, backgroundColor: '#F4F2EA', borderWidth: 1, borderColor: '#E8E2D5', flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 12, paddingHorizontal: 16, marginBottom: 14 },
  submitRecommendTitle: { color: '#111111', fontSize: 17, fontWeight: '900' },
  submitRecommendSub: { color: '#6E6A62', fontSize: 12, lineHeight: 16, fontWeight: '700', marginTop: 3 },
  audiusHero: { borderRadius: 26, backgroundColor: '#F4F6EE', borderWidth: 1, borderColor: '#E6EAD8', padding: 16, marginBottom: 14, gap: 12 },
  audiusHeroTitle: { color: '#111111', fontSize: 28, lineHeight: 31, fontWeight: '900' },
  audiusHeroText: { color: '#5F6459', fontSize: 13, lineHeight: 18, fontWeight: '700' },
  audiusSearchBox: { minHeight: 48, borderRadius: 24, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E3E3E3', flexDirection: 'row', alignItems: 'center', gap: 9, paddingHorizontal: 13 },
  audiusSearchInput: { flex: 1, minWidth: 0, color: '#111111', fontSize: 14, fontWeight: '800', paddingVertical: 0 },
  audiusSearchClear: { width: 28, height: 28, borderRadius: 14, backgroundColor: '#F1F1F1', alignItems: 'center', justifyContent: 'center' },
  audiusChipRail: { gap: 8, paddingRight: 4 },
  audiusChip: { minHeight: 34, borderRadius: 17, backgroundColor: '#111111', justifyContent: 'center', paddingHorizontal: 12 },
  audiusChipText: { color: '#FFFFFF', fontSize: 12, fontWeight: '900' },
  audiusList: { gap: 12 },
  audiusCard: { minHeight: 126, borderRadius: 22, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E9E9E9', flexDirection: 'row', gap: 12, padding: 10 },
  audiusArtworkWrap: { width: 104, height: 104, borderRadius: 18, overflow: 'hidden', backgroundColor: '#EFF2E8', position: 'relative' },
  audiusArtwork: { width: '100%', height: '100%' },
  audiusArtworkFallback: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  audiusPlayButton: { position: 'absolute', right: 8, bottom: 8, width: 38, height: 38, borderRadius: 19, backgroundColor: '#DFFF32', borderWidth: 1.2, borderColor: '#111111', alignItems: 'center', justifyContent: 'center' },
  audiusCopy: { flex: 1, minWidth: 0, justifyContent: 'center' },
  audiusMetaRow: { flexDirection: 'row', alignItems: 'center', gap: 5, marginBottom: 5 },
  audiusSource: { color: '#56724C', fontSize: 10, fontWeight: '900', letterSpacing: 0.7 },
  audiusDot: { color: '#9A9A9A', fontSize: 10, fontWeight: '900' },
  audiusDuration: { color: '#777777', fontSize: 11, fontWeight: '800' },
  audiusTitle: { color: '#111111', fontSize: 17, lineHeight: 20, fontWeight: '900' },
  audiusArtist: { color: '#6F6F6F', fontSize: 13, fontWeight: '800', marginTop: 4 },
  audiusActions: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 12 },
  audiusPrimaryAction: { flex: 1, minHeight: 38, borderRadius: 19, backgroundColor: '#DFFF32', borderWidth: 1.2, borderColor: '#111111', flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingHorizontal: 10 },
  audiusPrimaryActionText: { color: '#111111', fontSize: 12, fontWeight: '900' },
  audiusIconAction: { width: 38, height: 38, borderRadius: 19, backgroundColor: '#F2F2F2', alignItems: 'center', justifyContent: 'center' },
  audiusIconActionOn: { backgroundColor: '#DFFF32', borderWidth: 1.2, borderColor: '#111111' },
  noteList: { gap: 14 },
  recommendGrid: { flexDirection: 'row', gap: 3, alignItems: 'flex-start' },
  recommendColumn: { flex: 1, gap: 3 },
  recommendCard: { borderRadius: 18, overflow: 'hidden', position: 'relative', padding: 15, justifyContent: 'space-between' },
  recommendCardImage: { ...StyleSheet.absoluteFillObject, width: '100%', height: '100%' },
  recommendCardShade: { ...StyleSheet.absoluteFillObject, backgroundColor: 'transparent' },
  recommendCardShadeOnImage: { backgroundColor: 'rgba(0,0,0,0.20)' },
  recommendCardCopy: { gap: 6 },
  recommendSmall: { color: '#2D2D2D', fontSize: 11, fontWeight: '700' },
  recommendCardTitle: { color: '#111111', fontSize: 24, lineHeight: 25, fontWeight: '500', letterSpacing: 0 },
  recommendCardMeta: { color: '#2D2D2D', fontSize: 11, fontWeight: '700' },
  recommendTextOnImage: { color: '#FFFFFF', textShadowColor: 'rgba(0,0,0,0.32)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 4 },
  recommendReadMore: { flexDirection: 'row', alignItems: 'center', gap: 4, marginTop: 18 },
  recommendReadText: { color: '#111111', fontSize: 11, fontWeight: '900' },
  recommendReadTextOnImage: { color: '#FFFFFF' },
  recommendLoading: { minHeight: 260, alignItems: 'center', justifyContent: 'center' },
  recommendEmpty: { minHeight: 280, borderRadius: 22, backgroundColor: '#F7F7F7', alignItems: 'center', justifyContent: 'center', padding: 24 },
  recommendEmptyTitle: { color: '#111111', fontSize: 19, fontWeight: '900', marginTop: 10 },
  recommendEmptyText: { color: '#777777', fontSize: 13, lineHeight: 18, textAlign: 'center', marginTop: 6, fontWeight: '700' },
  recommendEmptyButton: { marginTop: 16, minHeight: 44, borderRadius: 22, backgroundColor: '#111111', justifyContent: 'center', paddingHorizontal: 18 },
  recommendEmptyButtonText: { color: '#FFFFFF', fontSize: 13, fontWeight: '900' },

  center: { paddingTop: 100, alignItems: 'center' },
});
