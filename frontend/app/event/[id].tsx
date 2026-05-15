import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Dimensions,
  Image,
  Linking,
  Platform,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView, useSafeAreaInsets } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../../src/api/client';
import { colors } from '../../src/utils/theme';
import { openSafeUrl } from '../../src/utils/safeLinking';

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

type EventParams = {
  id?: string;
  placeId?: string;
  title?: string;
  host?: string;
  venue?: string;
  address?: string;
  image?: string;
  schedule?: string;
  weekday?: string;
  month?: string;
  day?: string;
  description?: string;
  attendees?: string;
  lat?: string;
  lng?: string;
  eventUrl?: string;
  source?: string;
};

const getParam = (value?: string | string[]) => (Array.isArray(value) ? value[0] : value || '');

function fallbackDateParts() {
  const date = new Date();
  return {
    weekday: WEEKDAYS[date.getDay()],
    month: MONTHS[date.getMonth()],
    day: `${date.getDate()}`.padStart(2, '0'),
  };
}

export default function EventDetailScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<EventParams>();
  const placeId = getParam(params.placeId);

  const [place, setPlace] = useState<any>(null);
  const [loadingPlace, setLoadingPlace] = useState(false);

  const loadPlace = useCallback(async () => {
    if (!placeId) return;
    setLoadingPlace(true);
    try {
      const response = await api.get(`/mapbox-places/${encodeURIComponent(placeId)}`);
      setPlace(response.data);
    } catch (error) {
      console.log('Error loading event place:', error);
    } finally {
      setLoadingPlace(false);
    }
  }, [placeId]);

  useEffect(() => {
    loadPlace();
  }, [loadPlace]);

  const dateParts = useMemo(() => {
    const fallback = fallbackDateParts();
    return {
      weekday: getParam(params.weekday) || fallback.weekday,
      month: getParam(params.month) || fallback.month,
      day: getParam(params.day) || fallback.day,
    };
  }, [params.weekday, params.month, params.day]);

  const title = getParam(params.title) || place?.name || 'Event';
  const host = getParam(params.host) || 'Flames local guide';
  const venue = place?.name || getParam(params.venue) || 'Nearby venue';
  const address = place?.address || getParam(params.address) || venue;
  const schedule = getParam(params.schedule) || `${dateParts.weekday}, ${dateParts.month} ${Number(dateParts.day)} at 08:00PM`;
  const attendees = Number(getParam(params.attendees) || 3);
  const heroImage = place?.photos?.[0] || getParam(params.image);
  const description = getParam(params.description)
    || 'A local plan picked from your preferences. Confirm the exact time, ticket rules, and lineup before you go.';
  const eventUrl = getParam(params.eventUrl);

  const lat = place?.lat ?? Number(getParam(params.lat));
  const lng = place?.lng ?? Number(getParam(params.lng));

  const openDirections = () => {
    if (place?.url) {
      openSafeUrl(place.url);
      return;
    }

    const label = encodeURIComponent(address || venue);
    const latLngReady = Number.isFinite(lat) && Number.isFinite(lng);
    const url = Platform.select({
      ios: latLngReady ? `maps:0,0?q=${label}@${lat},${lng}` : `maps:0,0?q=${label}`,
      android: latLngReady ? `geo:${lat},${lng}?q=${lat},${lng}(${label})` : `geo:0,0?q=${label}`,
      default: `https://www.google.com/maps/search/?api=1&query=${label}`,
    });
    if (url) Linking.openURL(url);
  };

  const openTickets = () => {
    if (eventUrl) {
      openSafeUrl(eventUrl);
      return;
    }
    if (place?.website) {
      openSafeUrl(place.website);
      return;
    }
    openDirections();
  };

  return (
    <SafeAreaView style={styles.safeArea} edges={['top']}>
      <View style={styles.screen}>
        <View style={styles.header}>
          <TouchableOpacity style={styles.headerBtn} onPress={() => router.back()} activeOpacity={0.75}>
            <Ionicons name="arrow-back" size={30} color={colors.textPrimary} />
          </TouchableOpacity>
          <Text style={styles.headerTitle}>Event</Text>
          <TouchableOpacity style={styles.headerBtn} activeOpacity={0.75}>
            <Ionicons name="ellipsis-horizontal" size={30} color={colors.textPrimary} />
          </TouchableOpacity>
        </View>

        <ScrollView
          showsVerticalScrollIndicator={false}
          contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + 132 }]}
        >
          <View style={styles.hero}>
            {heroImage ? (
              <Image source={{ uri: heroImage }} style={styles.heroImage} resizeMode="cover" />
            ) : (
              <View style={styles.heroFallback}>
                <View style={styles.heroCurveOne} />
                <View style={styles.heroCurveTwo} />
                <Ionicons name="calendar-outline" size={46} color="#FFFFFF" />
              </View>
            )}
            {loadingPlace && (
              <View style={styles.heroLoading}>
                <ActivityIndicator size="small" color={colors.textPrimary} />
              </View>
            )}
          </View>

          <View style={styles.titleRow}>
            <View style={styles.titleCopy}>
              <Text style={styles.eventTitle} numberOfLines={3}>{title}</Text>
              <Text style={styles.hostLine} numberOfLines={1}>
                Hosted by <Text style={styles.hostName}>{host}</Text>
              </Text>
              <View style={styles.attendeeRow}>
                <View style={styles.avatarStack}>
                  {[0, 1, 2].map((n) => (
                    <View key={n} style={[styles.avatar, { left: n * 28, backgroundColor: ['#DAD9D4', '#C8C1B2', '#B7B5AE'][n] }]} />
                  ))}
                </View>
                <Text style={styles.attendeeText}>{attendees} people are going</Text>
              </View>
            </View>

            <View style={styles.dateCard}>
              <View style={styles.dateTop}><Text style={styles.dateWeekday}>{dateParts.weekday}</Text></View>
              <Text style={styles.dateMonth}>{dateParts.month}</Text>
              <Text style={styles.dateDay}>{dateParts.day}</Text>
            </View>
          </View>

          <View style={styles.actionRow}>
            <TouchableOpacity style={styles.roundAction} activeOpacity={0.8}>
              <Ionicons name="document-text-outline" size={24} color={colors.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.roundAction} activeOpacity={0.8}>
              <Ionicons name="arrow-redo-outline" size={24} color={colors.textPrimary} />
            </TouchableOpacity>
            <TouchableOpacity style={styles.ticketBtn} onPress={openTickets} activeOpacity={0.85}>
              <Text style={styles.ticketText}>Get tickets</Text>
            </TouchableOpacity>
          </View>

          <View style={styles.infoBlock}>
            <View style={styles.infoRow}>
              <Ionicons name="time-outline" size={30} color={colors.textPrimary} />
              <Text style={styles.infoText}>{schedule}</Text>
            </View>
            <TouchableOpacity style={styles.infoRow} onPress={openDirections} activeOpacity={0.8}>
              <Ionicons name="location-outline" size={30} color={colors.textPrimary} />
              <Text style={styles.infoText} numberOfLines={2}>{address}</Text>
            </TouchableOpacity>
          </View>

          <View style={styles.descriptionBlock}>
            <Text style={styles.sectionTitle}>Description</Text>
            <Text style={styles.description}>{description}</Text>
          </View>
        </ScrollView>

        <View style={[styles.bottomBar, { paddingBottom: insets.bottom + 14 }]}>
          <TouchableOpacity style={styles.rsvpBtn} onPress={openTickets} activeOpacity={0.9}>
            <Text style={styles.rsvpText}>RSVP</Text>
          </TouchableOpacity>
        </View>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: colors.white,
  },
  screen: {
    flex: 1,
    backgroundColor: colors.white,
  },
  header: {
    height: 82,
    borderBottomWidth: 1.5,
    borderBottomColor: colors.textPrimary,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 22,
  },
  headerBtn: {
    width: 48,
    height: 48,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: 21,
    fontWeight: '500',
    color: colors.textPrimary,
  },
  content: {
    paddingBottom: 120,
  },
  hero: {
    width: '100%',
    height: Math.min(214, SCREEN_WIDTH * 0.46),
    borderBottomLeftRadius: 16,
    borderBottomRightRadius: 16,
    borderWidth: 1.5,
    borderTopWidth: 0,
    borderColor: colors.textPrimary,
    overflow: 'hidden',
    backgroundColor: '#41D34C',
  },
  heroImage: {
    width: '100%',
    height: '100%',
  },
  heroFallback: {
    flex: 1,
    backgroundColor: '#41D34C',
    justifyContent: 'center',
    alignItems: 'center',
    overflow: 'hidden',
  },
  heroCurveOne: {
    position: 'absolute',
    width: SCREEN_WIDTH * 1.2,
    height: 72,
    borderRadius: 44,
    backgroundColor: colors.white,
    left: -90,
    bottom: 18,
    transform: [{ rotate: '-13deg' }],
  },
  heroCurveTwo: {
    position: 'absolute',
    width: SCREEN_WIDTH * 0.7,
    height: 76,
    borderRadius: 42,
    backgroundColor: colors.white,
    right: -54,
    top: 4,
    transform: [{ rotate: '18deg' }],
  },
  heroLoading: {
    position: 'absolute',
    right: 14,
    bottom: 14,
    width: 34,
    height: 34,
    borderRadius: 17,
    backgroundColor: 'rgba(255,255,255,0.86)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  titleRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 14,
    paddingHorizontal: 18,
    paddingTop: 32,
  },
  titleCopy: {
    flex: 1,
    minWidth: 0,
  },
  eventTitle: {
    color: colors.textPrimary,
    fontSize: 31,
    lineHeight: 35,
    fontWeight: '500',
  },
  hostLine: {
    marginTop: 8,
    color: '#333333',
    fontSize: 18,
  },
  hostName: {
    textDecorationLine: 'underline',
  },
  attendeeRow: {
    marginTop: 14,
    minHeight: 44,
    flexDirection: 'row',
    alignItems: 'center',
  },
  avatarStack: {
    width: 92,
    height: 42,
    position: 'relative',
  },
  avatar: {
    position: 'absolute',
    top: 0,
    width: 42,
    height: 42,
    borderRadius: 21,
    borderWidth: 1.5,
    borderColor: colors.textPrimary,
  },
  attendeeText: {
    flex: 1,
    color: '#424242',
    fontSize: 14,
    fontWeight: '500',
  },
  dateCard: {
    width: 84,
    borderWidth: 1.5,
    borderColor: colors.textPrimary,
    borderRadius: 12,
    overflow: 'hidden',
    backgroundColor: colors.white,
    alignItems: 'center',
  },
  dateTop: {
    width: '100%',
    backgroundColor: '#FBF84A',
    borderBottomWidth: 1.5,
    borderBottomColor: colors.textPrimary,
    paddingVertical: 6,
    alignItems: 'center',
  },
  dateWeekday: {
    color: colors.textPrimary,
    fontSize: 16,
    fontWeight: '500',
  },
  dateMonth: {
    color: colors.textPrimary,
    fontSize: 28,
    lineHeight: 34,
    marginTop: 10,
  },
  dateDay: {
    color: colors.textPrimary,
    fontSize: 35,
    lineHeight: 42,
    fontWeight: '500',
    marginBottom: 8,
  },
  actionRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 18,
    paddingHorizontal: 18,
    paddingTop: 26,
  },
  roundAction: {
    width: 54,
    height: 54,
    borderRadius: 27,
    borderWidth: 1.5,
    borderColor: colors.textPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.white,
  },
  ticketBtn: {
    minWidth: 132,
    height: 50,
    borderRadius: 14,
    borderWidth: 1.5,
    borderColor: colors.textPrimary,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 22,
    backgroundColor: colors.white,
  },
  ticketText: {
    color: colors.textPrimary,
    fontSize: 18,
    fontWeight: '500',
  },
  infoBlock: {
    paddingHorizontal: 22,
    paddingTop: 28,
    gap: 18,
  },
  infoRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 20,
  },
  infoText: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: 20,
    lineHeight: 26,
  },
  descriptionBlock: {
    paddingHorizontal: 18,
    paddingTop: 34,
  },
  sectionTitle: {
    color: colors.textPrimary,
    fontSize: 22,
    fontWeight: '500',
    marginBottom: 22,
  },
  description: {
    color: '#2B2B2B',
    fontSize: 20,
    lineHeight: 31,
  },
  bottomBar: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    paddingHorizontal: 18,
    paddingTop: 14,
    backgroundColor: colors.white,
  },
  rsvpBtn: {
    height: 64,
    borderRadius: 32,
    borderWidth: 1.5,
    borderColor: colors.textPrimary,
    backgroundColor: '#41D34C',
    justifyContent: 'center',
    alignItems: 'center',
  },
  rsvpText: {
    color: '#050505',
    fontSize: 22,
    fontWeight: '500',
  },
});
