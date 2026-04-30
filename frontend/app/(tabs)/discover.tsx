import React, { useState, useEffect, useCallback } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView,
  RefreshControl, Dimensions, ActivityIndicator,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as Location from 'expo-location';
import api from '../../src/api/client';
import { useAuthStore } from '../../src/store/authStore';
import { colors } from '../../src/utils/theme';
import { useI18n } from '../../src/utils/i18n';
import { requireVerifiedPhone } from '../../src/utils/phoneVerification';

const { width: SW } = Dimensions.get('window');
const SHELF_CARD = Math.min(138, Math.max(118, (SW - 54) / 2.35));

const CITY_TABS = [
  { id: 'all', label: 'For You' },
  { id: 'nyc', label: 'New York' },
  { id: 'miami', label: 'Miami' },
  { id: 'la', label: 'LA' },
  { id: 'london', label: 'London' },
  { id: 'tokyo', label: 'Tokyo' },
  { id: 'paris', label: 'Paris' },
];

const DISCOVER_SHELVES = [
  {
    id: 'groups',
    label: 'Groups to Join',
    sub: 'Find people moving together.',
    type: 'gym',
    icon: 'people-outline',
    fallbackColor: '#DCEDE3',
    fallbackItems: ['Fitness Crew', 'Book Circle', 'Local Club'],
  },
  {
    id: 'events',
    label: 'Events',
    sub: 'Tonight, weekend, parks, markets, and venues.',
    type: 'stadium',
    icon: 'calendar-outline',
    fallbackColor: '#E1F3DF',
    fallbackItems: ['Night events tonight', 'Local farmers market', 'Bryant Park happenings'],
  },
] as const;

const EVENT_SEARCHES = [
  {
    id: 'tonight-clubs',
    title: 'Night events tonight',
    host: 'Flames nightlife guide',
    timing: { weekday: null, startHour: 20, endHour: 2 },
    shortTime: 'Tonight',
    fallbackVenue: 'Manhattan nightlife',
    placeType: 'night_club',
    keyword: 'club party nightlife',
    description: 'A nightlife pick shaped by your event preferences. Check tickets for the exact lineup before you go.',
  },
  {
    id: 'farmers-market',
    title: 'Local farmers market',
    host: 'Flames local guide',
    timing: { weekday: 1, startHour: 9, endHour: 14 },
    shortTime: 'Every Monday',
    fallbackVenue: 'Union Square area',
    placeType: 'tourist_attraction',
    keyword: 'farmers market',
    description: 'Fresh produce, neighborhood vendors, and a low-key city walk picked for local weekend and market interests.',
  },
  {
    id: 'bryant-park',
    title: 'Bryant Park happenings',
    host: 'Flames park guide',
    timing: { weekday: 6, startHour: 11, endHour: 19 },
    shortTime: 'This weekend',
    fallbackVenue: 'Bryant Park',
    placeType: 'park',
    keyword: 'Bryant Park events',
    description: 'A Bryant Park based plan for markets, public programming, or seasonal pop-ups.',
  },
  {
    id: 'live-music',
    title: 'Live music tonight',
    host: 'Flames music guide',
    timing: { weekday: null, startHour: 19, endHour: 23 },
    shortTime: 'Tonight',
    fallbackVenue: 'Lower Manhattan',
    placeType: 'bar',
    keyword: 'live music',
    description: 'A live night plan picked from your music and going-out signals.',
  },
  {
    id: 'movie-night',
    title: 'Movie night',
    host: 'Flames movie guide',
    timing: { weekday: null, startHour: 19, endHour: 22 },
    shortTime: 'Tonight',
    fallbackVenue: 'Manhattan cinema',
    placeType: 'movie_theater',
    keyword: 'movie film cinema',
    description: 'A movie plan picked from your entertainment and culture signals.',
  },
  {
    id: 'sports-night',
    title: 'Sports nearby',
    host: 'Flames sports guide',
    timing: { weekday: 6, startHour: 15, endHour: 18 },
    shortTime: 'This weekend',
    fallbackVenue: 'New York sports venue',
    placeType: 'stadium',
    keyword: 'sports game',
    description: 'A nearby sports venue pick shaped by your activity and fan interests.',
  },
] as const;

const CITY_COORDS: Record<string, { lat: number; lng: number }> = {
  all: { lat: 40.7128, lng: -74.006 },
  nyc: { lat: 40.7128, lng: -74.006 },
  miami: { lat: 25.7617, lng: -80.1918 },
  la: { lat: 34.0522, lng: -118.2437 },
  london: { lat: 51.5074, lng: -0.1278 },
  tokyo: { lat: 35.6762, lng: 139.6503 },
  paris: { lat: 48.8566, lng: 2.3522 },
};

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

type EventTiming = { weekday: number | null; startHour: number; endHour: number };

const routeParam = (value: any) => (value === undefined || value === null ? '' : String(value));

function getEventDate(targetWeekday: number | null) {
  const date = new Date();
  if (targetWeekday !== null) {
    const today = date.getDay();
    const delta = (targetWeekday - today + 7) % 7 || 7;
    date.setDate(date.getDate() + delta);
  }
  return date;
}

function clockLabel(date: Date) {
  let hour = date.getHours();
  const minute = `${date.getMinutes()}`.padStart(2, '0');
  const suffix = hour >= 12 ? 'PM' : 'AM';
  hour = hour % 12 || 12;
  return `${`${hour}`.padStart(2, '0')}:${minute}${suffix}`;
}

function buildEventTiming(template: EventTiming) {
  const start = getEventDate(template.weekday);
  start.setHours(template.startHour, 0, 0, 0);
  const end = new Date(start);
  end.setHours(template.endHour, 0, 0, 0);
  if (template.endHour <= template.startHour) end.setDate(end.getDate() + 1);

  return {
    weekday: WEEKDAYS[start.getDay()],
    month: MONTHS[start.getMonth()],
    day: `${start.getDate()}`.padStart(2, '0'),
    schedule: `${WEEKDAYS[start.getDay()]}, ${MONTHS[start.getMonth()]} ${start.getDate()} at ${clockLabel(start)} - ${clockLabel(end)}`,
  };
}

function buildEventCard(place: any, search: typeof EVENT_SEARCHES[number], index: number) {
  const timing = buildEventTiming(search.timing);
  const placeName = place?.name || search.fallbackVenue;
  const address = place?.vicinity || place?.formatted_address || search.fallbackVenue;

  return {
    ...place,
    event: true,
    event_source: 'google_places',
    event_id: `${search.id}-${place?.place_id || index}`.replace(/[^a-zA-Z0-9_-]/g, '-'),
    event_title: search.title,
    event_host: search.host,
    event_venue: placeName,
    event_address: address,
    event_description: search.description,
    event_time_label: search.shortTime,
    event_schedule: timing.schedule,
    event_weekday: timing.weekday,
    event_month: timing.month,
    event_day: timing.day,
    attendees: 3 + (index % 6),
  };
}

async function loadGoogleEventFallback(coords: { lat: number; lng: number }) {
  const batches = await Promise.all(
    EVENT_SEARCHES.map(async (search, searchIndex) => {
      try {
        const r = await api.get('/google-places/nearby', {
          params: {
            lat: coords.lat,
            lng: coords.lng,
            radius: 40000,
            type: search.placeType,
            keyword: search.keyword,
          },
        });
        const places = Array.isArray(r.data) ? r.data : [];
        return places.slice(0, 2).map((place: any, placeIndex: number) =>
          buildEventCard(place, search, searchIndex * 10 + placeIndex)
        );
      } catch {
        return [];
      }
    })
  );

  const seen = new Set<string>();
  return batches.flat().filter((event) => {
    const key = event.place_id || event.event_id;
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, 8);
}

function eventbriteEmptyCard(detail?: string) {
  const now = buildEventTiming({ weekday: null, startHour: 20, endHour: 22 });
  return {
    event: true,
    empty: true,
    fallback: true,
    event_source: 'eventbrite',
    event_id: 'eventbrite-empty',
    place_id: 'eventbrite-empty',
    event_title: 'No live Eventbrite events',
    event_host: 'Eventbrite',
    event_venue: 'No live results for this account',
    event_address: 'Eventbrite did not return local events',
    event_description: detail || 'Eventbrite is connected, but it did not return live local events for this account.',
    event_time_label: 'No events',
    event_schedule: now.schedule,
    event_weekday: now.weekday,
    event_month: now.month,
    event_day: now.day,
    attendees: 0,
  };
}

export default function DiscoverScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const { t } = useI18n();
  const [tab, setTab] = useState('all');
  const [shelfPlaces, setShelfPlaces] = useState<Record<string, any[]>>({});
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [people, setPeople] = useState<any[]>([]);
  const [userCoords, setUserCoords] = useState<{ lat: number; lng: number } | null>(null);

  const loadPeople = useCallback(async () => {
    try {
      const r = await api.get('/discover/suggested-users');
      setPeople(Array.isArray(r.data) ? r.data : []);
    } catch {}
  }, []);

  const loadUserCoords = useCallback(async () => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') return;
      const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
      setUserCoords({ lat: loc.coords.latitude, lng: loc.coords.longitude });
    } catch {}
  }, []);

  const activeCoords = useCallback(
    () => (tab === 'all' && userCoords ? userCoords : (CITY_COORDS[tab] || CITY_COORDS.all)),
    [tab, userCoords]
  );

  const loadEventPlaces = useCallback(async (coords: { lat: number; lng: number }) => {
    const location = CITY_TABS.find((c) => c.id === tab)?.label || 'New York';
    let emptyDetail = '';
    try {
      const r = await api.get('/events/personalized', {
        params: {
          lat: coords.lat,
          lng: coords.lng,
          location: user?.city || location,
          city: user?.city || location,
          interests: user?.interests || '',
          looking_for: user?.looking_for || '',
          limit: 12,
        },
      });
      const events = Array.isArray(r.data?.events) ? r.data.events : [];
      if (events.length > 0) return events.slice(0, 8);
      const detail = typeof r.data?.detail === 'string' ? r.data.detail : '';
      const errors = Array.isArray(r.data?.errors) ? r.data.errors.join(', ') : '';
      emptyDetail = detail || (errors ? `Eventbrite returned no events. Status: ${errors}.` : '');
    } catch {
      emptyDetail = 'Eventbrite events could not load from the backend preview.';
    }

    const googleEvents = await loadGoogleEventFallback(coords);
    return googleEvents.length > 0 ? googleEvents : [eventbriteEmptyCard(emptyDetail)];
  }, [tab, user?.city, user?.interests, user?.looking_for]);

  const loadShelfPlaces = useCallback(async () => {
    const coords = activeCoords();
    const entries = await Promise.all(DISCOVER_SHELVES.map(async (b) => {
      try {
        if (b.id === 'events') {
          return [b.id, await loadEventPlaces(coords)] as const;
        } else {
          const r = await api.get('/google-places/nearby', { params: { lat: coords.lat, lng: coords.lng, radius: 40000, type: b.type } });
          const places = Array.isArray(r.data) ? r.data : [];
          return [b.id, places.slice(0, 8)] as const;
        }
      } catch {
        return [b.id, []] as const;
      }
    }));
    setShelfPlaces(Object.fromEntries(entries));
  }, [activeCoords, loadEventPlaces]);

  useEffect(() => {
    let mounted = true;
    async function bootstrap() {
      setLoading(true);
      await Promise.all([loadPeople(), loadUserCoords()]);
      if (mounted) setLoading(false);
    }
    bootstrap();
    return () => { mounted = false; };
  }, [loadPeople, loadUserCoords]);

  useEffect(() => { loadShelfPlaces(); }, [loadShelfPlaces]);

  const onRefresh = useCallback(async () => {
    setRefreshing(true); await Promise.all([loadPeople(), loadShelfPlaces()]); setRefreshing(false);
  }, [loadPeople, loadShelfPlaces]);

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
        ) : (
          <>
            {/* Search */}
            <View style={s.searchWrap}>
              <View style={s.searchBar}>
                <Ionicons name="search" size={18} color="#999" />
                <Text style={s.searchPh}>{t('searchPrompt')}</Text>
              </View>
            </View>

            {/* People Profiles */}
            <View style={s.peopleSection}>
              <Text style={s.peopleSectionTitle}>{t('people')}</Text>
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
                  {people.map((u: any) => (
                    <TouchableOpacity key={u.id} style={s.personCard} activeOpacity={0.9}
                      onPress={() => router.push(`/user/${u.id}` as any)}>
                      {u.profile_image ? (
                        <Image source={{ uri: u.profile_image }} style={s.personImg} />
                      ) : (
                        <View style={[s.personImg, { backgroundColor: '#F0F0F0', justifyContent: 'center', alignItems: 'center' }]}>
                          <Text style={s.personInit}>{(u.full_name || 'U')[0]}</Text>
                        </View>
                      )}
                      <Text style={s.personName} numberOfLines={1}>{u.full_name}</Text>
                      <Text style={s.personBio} numberOfLines={2}>{u.bio || u.city || ''}</Text>
                    </TouchableOpacity>
                  ))}
              </ScrollView>
            </View>

            {/* Discover shelves */}
            <View style={s.shelfRegion}>
              {DISCOVER_SHELVES.map((section) => {
                const places = shelfPlaces[section.id] || [];
                const cards = places.length > 0
                  ? places
                  : section.fallbackItems.map((name, index) => ({ place_id: `${section.id}-${index}`, name, fallback: true }));

                return (
                  <View key={section.id} style={s.shelfSection}>
                    <TouchableOpacity
                      style={s.shelfHeader}
                      activeOpacity={0.75}
                      onPress={() => router.push(`/category/${section.id}` as any)}
                    >
                      <Text style={s.shelfTitle}>{section.label}</Text>
                      <Ionicons name="chevron-forward" size={20} color="#5D5D5D" />
                    </TouchableOpacity>
                    <Text style={s.shelfSub}>{section.sub}</Text>

                    <ScrollView
                      horizontal
                      showsHorizontalScrollIndicator={false}
                      contentContainerStyle={s.shelfScroll}
                    >
                      {cards.map((item: any, index: number) => {
                        const hasPhoto = !!item.photo_url;
                        const isEvent = section.id === 'events';
                        const title = isEvent ? (item.event_title || item.name || section.label) : (item.name || section.label);
                        const meta = isEvent
                          ? `${item.event_time_label || 'Nearby'} - ${item.event_venue || item.name || item.vicinity || 'Local'}`
                          : item.vicinity || item.formatted_address || (item.rating ? `${item.rating} stars` : section.label);

                        return (
                          <TouchableOpacity
                            key={item.place_id || `${section.id}-${index}`}
                            style={s.shelfCard}
                            activeOpacity={0.88}
                            onPress={() => {
                              if (item.empty) return;
                              if (isEvent) {
                                router.push({
                                  pathname: '/event/[id]',
                                  params: {
                                    id: routeParam(item.event_id || item.place_id || `${section.id}-${index}`),
                                    placeId: item.fallback ? '' : routeParam(item.place_id),
                                    title: routeParam(item.event_title || item.name || 'Event'),
                                    host: routeParam(item.event_host || 'Flames local guide'),
                                    venue: routeParam(item.event_venue || item.name),
                                    address: routeParam(item.event_address || item.vicinity || item.formatted_address),
                                    image: routeParam(item.photo_url),
                                    schedule: routeParam(item.event_schedule),
                                    weekday: routeParam(item.event_weekday),
                                    month: routeParam(item.event_month),
                                    day: routeParam(item.event_day),
                                    description: routeParam(item.event_description),
                                    attendees: routeParam(item.attendees || 3),
                                    lat: routeParam(item.lat),
                                    lng: routeParam(item.lng),
                                    eventUrl: routeParam(item.event_url || item.url),
                                    source: routeParam(item.event_source || 'eventbrite'),
                                  },
                                } as any);
                              } else if (item.fallback || !item.place_id) {
                                router.push(`/category/${section.id}` as any);
                              } else {
                                router.push(`/place/${item.place_id}` as any);
                              }
                            }}
                          >
                            <View style={[s.shelfImage, s.shelfFallback, { backgroundColor: section.fallbackColor }]}>
                              <Ionicons name={section.icon as keyof typeof Ionicons.glyphMap} size={28} color="#181818" />
                              {isEvent && <Text style={s.eventFallbackLabel}>{item.event_time_label || 'Event'}</Text>}
                              {hasPhoto && (
                                <Image source={{ uri: item.photo_url }} style={s.shelfImageOverlay} resizeMode="cover" />
                              )}
                            </View>
                            <Text style={s.shelfCardTitle} numberOfLines={2}>{title}</Text>
                            <Text style={s.shelfCardMeta} numberOfLines={1}>{meta}</Text>
                          </TouchableOpacity>
                        );
                      })}
                    </ScrollView>
                  </View>
                );
              })}
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

  shelfRegion: { backgroundColor: colors.white, paddingTop: 8, paddingBottom: 18 },
  shelfSection: { paddingTop: 12, paddingBottom: 4 },
  shelfHeader: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16 },
  shelfTitle: { fontSize: 20, fontWeight: '900', color: '#050505', lineHeight: 24 },
  shelfSub: { fontSize: 12, color: '#6E6E6E', paddingHorizontal: 16, marginTop: 2, marginBottom: 10 },
  shelfScroll: { gap: 10, paddingHorizontal: 16, paddingRight: 24 },
  shelfCard: { width: SHELF_CARD },
  shelfImage: { width: SHELF_CARD, height: SHELF_CARD, borderRadius: 6 },
  shelfImageOverlay: { position: 'absolute', width: SHELF_CARD, height: SHELF_CARD, borderRadius: 6 },
  shelfFallback: { justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: colors.borderSubtle },
  eventFallbackLabel: { marginTop: 8, fontSize: 11, fontWeight: '800', color: colors.accentPrimary },
  shelfCardTitle: { fontSize: 13, fontWeight: '700', color: '#050505', lineHeight: 16, marginTop: 7 },
  shelfCardMeta: { fontSize: 11, color: '#777', lineHeight: 14, marginTop: 2 },

  center: { paddingTop: 100, alignItems: 'center' },
});
