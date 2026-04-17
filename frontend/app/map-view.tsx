import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  Linking,
  Platform,
  Dimensions,
  ScrollView,
  Animated,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as Location from 'expo-location';
import { colors } from '../src/utils/theme';
import api from '../src/api/client';

let WebView: any = null;
try { WebView = require('react-native-webview').WebView; } catch {}


const { width: SW, height: SH } = Dimensions.get('window');
const GKEY = 'AIzaSyC2o8RvjURwDSbOTOs2ynynAR7fSQUMjwU';

const PLACE_TYPES = [
  { id: 'restaurant', label: 'Restaurants', icon: 'restaurant' },
  { id: 'cafe', label: 'Cafes', icon: 'cafe' },
  { id: 'bar', label: 'Bars', icon: 'wine' },
  { id: 'store', label: 'Shops', icon: 'bag-handle' },
  { id: 'gym', label: 'Gyms', icon: 'barbell' },
  { id: 'park', label: 'Parks', icon: 'leaf' },
];

// Warm modern map style (Popeyes/Chick-fil-A inspired)
const MAP_STYLE = JSON.stringify([
  {"featureType":"all","elementType":"geometry","stylers":[{"color":"#F5F0EB"}]},
  {"featureType":"all","elementType":"labels.text.fill","stylers":[{"color":"#5C4033"}]},
  {"featureType":"all","elementType":"labels.text.stroke","stylers":[{"color":"#FFFFFF"},{"weight":3}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#C5DAE8"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#FFF3E0"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#E8D5B7"}]},
  {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#FFFFFF"}]},
  {"featureType":"road.local","elementType":"geometry.fill","stylers":[{"color":"#FFFFFF"}]},
  {"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#EDE8E0"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#F0ECE5"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#E5DED3"}]},
  {"featureType":"poi","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#D4E6C3"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative","elementType":"geometry.stroke","stylers":[{"color":"#D4C8B8"}]}
]);

export default function MapViewScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ type: string }>();
  const [places, setPlaces] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [lat, setLat] = useState(40.7128);
  const [lng, setLng] = useState(-74.006);
  const [cityName, setCityName] = useState('New York');
  const [selected, setSelected] = useState<any>(null);
  const [activeType, setActiveType] = useState(params.type || 'restaurant');
  const cardAnim = useRef(new Animated.Value(200)).current;
  const wvRef = useRef<any>(null);

  useEffect(() => {
    (async () => {
      try {
        const { status } = await Location.requestForegroundPermissionsAsync();
        if (status === 'granted') {
          const loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.Balanced });
          setLat(loc.coords.latitude);
          setLng(loc.coords.longitude);
          try {
            const geo = await Location.reverseGeocodeAsync({ latitude: loc.coords.latitude, longitude: loc.coords.longitude });
            if (geo[0]) setCityName(geo[0].city || geo[0].district || 'Your Area');
          } catch {}
        }
      } catch {}
    })();
  }, []);

  useEffect(() => { loadPlaces(); }, [lat, lng, activeType]);

  useEffect(() => {
    if (selected) {
      Animated.spring(cardAnim, { toValue: 0, useNativeDriver: true, friction: 8 }).start();
    } else {
      Animated.timing(cardAnim, { toValue: 200, duration: 200, useNativeDriver: true }).start();
    }
  }, [selected]);

  const loadPlaces = async () => {
    setLoading(true);
    try {
      const r = await api.get('/google-places/nearby', { params: { type: activeType, lat, lng, radius: 5000 } });
      setPlaces(r.data);
    } catch (e) { console.log('Places error', e); }
    finally { setLoading(false); }
  };

  const openNav = (p: any) => {
    const u = Platform.select({
      ios: `maps:0,0?q=${encodeURIComponent(p.name)}@${p.lat},${p.lng}`,
      android: `geo:${p.lat},${p.lng}?q=${p.lat},${p.lng}(${encodeURIComponent(p.name)})`,
      default: `https://www.google.com/maps/dir/?api=1&destination=${p.lat},${p.lng}`,
    });
    if (u) Linking.openURL(u);
  };

  const handleMsg = (e: any) => {
    try {
      const d = JSON.parse(e.nativeEvent.data);
      if (d.type === 'select' && d.idx !== undefined) setSelected(places[d.idx]);
      if (d.type === 'deselect') setSelected(null);
    } catch {}
  };

  const mapHTML = useCallback(() => {
    const markerColor = '#2D6A4F';
    const markers = places.map((p, i) => `
      (function(){
        var el = document.createElement('div');
        el.className = 'pin';
        el.innerHTML = '<div class="pin-body" style="background:${p.open_now === false ? '#B91C1C' : markerColor}"><span>${i+1}</span></div><div class="pin-tail" style="border-top-color:${p.open_now === false ? '#B91C1C' : markerColor}"></div>';
        var ov = new google.maps.OverlayView();
        ov.pos = new google.maps.LatLng(${p.lat||lat},${p.lng||lng});
        ov.onAdd = function(){ this.getPanes().floatPane.appendChild(el); };
        ov.draw = function(){ var pt = this.getProjection().fromLatLngToDivPixel(this.pos); if(pt){el.style.left=(pt.x-16)+'px';el.style.top=(pt.y-44)+'px';} };
        ov.onRemove = function(){ el.remove(); };
        ov.setMap(map);
        el.onclick = function(e){
          e.stopPropagation();
          map.panTo(ov.pos);
          window.ReactNativeWebView.postMessage(JSON.stringify({type:'select',idx:${i}}));
          document.querySelectorAll('.pin-body').forEach(function(p){p.style.transform='scale(1)';});
          el.querySelector('.pin-body').style.transform='scale(1.3)';
        };
      })();
    `).join('\n');

    return `<!DOCTYPE html><html><head>
    <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
    <style>
    *{margin:0;padding:0;box-sizing:border-box}
    html,body,#map{width:100%;height:100%}
    .pin{position:absolute;cursor:pointer;z-index:10;transition:transform .15s}
    .pin-body{width:32px;height:32px;border-radius:50%;display:flex;align-items:center;justify-content:center;
      box-shadow:0 2px 8px rgba(0,0,0,.25);border:2.5px solid #fff;transition:transform .2s cubic-bezier(.175,.885,.32,1.275)}
    .pin-body span{color:#fff;font-size:12px;font-weight:800;font-family:-apple-system,sans-serif}
    .pin-tail{width:0;height:0;border-left:6px solid transparent;border-right:6px solid transparent;border-top:8px solid;margin:auto;margin-top:-2px}
    .user-dot{width:16px;height:16px;border-radius:50%;background:#3B82F6;border:3px solid #fff;box-shadow:0 0 0 4px rgba(59,130,246,.25);position:absolute;z-index:999}
    .pulse{position:absolute;width:60px;height:60px;border-radius:50%;background:rgba(59,130,246,.12);animation:pulse 2s infinite;z-index:998}
    @keyframes pulse{0%{transform:scale(.5);opacity:1}100%{transform:scale(2);opacity:0}}
    </style></head><body>
    <div id="map"></div>
    <script>
    function initMap(){
      var map = new google.maps.Map(document.getElementById('map'),{
        center:{lat:${lat},lng:${lng}},zoom:14,
        mapTypeControl:false,streetViewControl:false,fullscreenControl:false,
        zoomControl:false,
        gestureHandling:'greedy',
        styles:${MAP_STYLE}
      });

      // User location with pulse
      var userOv = new google.maps.OverlayView();
      userOv.onAdd = function(){
        var d = document.createElement('div');
        d.style.position='relative';
        d.innerHTML='<div class="pulse"></div><div class="user-dot"></div>';
        this.el = d; this.getPanes().floatPane.appendChild(d);
      };
      userOv.draw = function(){
        var pt = this.getProjection().fromLatLngToDivPixel(new google.maps.LatLng(${lat},${lng}));
        if(pt){this.el.style.position='absolute';this.el.style.left=(pt.x-30)+'px';this.el.style.top=(pt.y-30)+'px';}
      };
      userOv.onRemove = function(){this.el.remove();};
      userOv.setMap(map);

      ${markers}

      map.addListener('click',function(){
        window.ReactNativeWebView.postMessage(JSON.stringify({type:'deselect'}));
        document.querySelectorAll('.pin-body').forEach(function(p){p.style.transform='scale(1)';});
      });
    }
    </script>
    <script src="https://maps.googleapis.com/maps/api/js?key=${GKEY}&libraries=places&callback=initMap" async defer></script>
    <script>
    window.onerror = function(msg) {
      document.getElementById('map').innerHTML = '<div style="display:flex;flex-direction:column;align-items:center;justify-content:center;height:100%;font-family:-apple-system,sans-serif;color:#999"><p style="font-size:16px;font-weight:600">Maps API Loading</p><p style="font-size:13px;margin-top:8px;text-align:center;padding:0 20px">Please enable Maps JavaScript API and Places API in your Google Cloud Console for this key.</p></div>';
    };
    </script>
    </body></html>`;
  }, [places, lat, lng]);

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      {/* Minimal Header */}
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color="#1B4332" />
        </TouchableOpacity>
        <View style={{ flex: 1 }}>
          <Text style={s.cityName}>{cityName}</Text>
          <Text style={s.subtitle}>{places.length} places nearby</Text>
        </View>
        <TouchableOpacity style={s.locateBtn} onPress={loadPlaces}>
          <Ionicons name="locate" size={20} color="#2D6A4F" />
        </TouchableOpacity>
      </View>

      {/* Filter Chips - scrollable on top of map */}
      <View style={s.chipBar}>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ paddingHorizontal: 16, gap: 8 }}>
          {PLACE_TYPES.map((t) => (
            <TouchableOpacity
              key={t.id}
              style={[s.chip, activeType === t.id && s.chipActive]}
              onPress={() => { setActiveType(t.id); setSelected(null); }}
            >
              <Ionicons name={t.icon as any} size={14} color={activeType === t.id ? '#FFF' : '#5C4033'} />
              <Text style={[s.chipText, activeType === t.id && s.chipTextActive]}>{t.label}</Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>

      {/* Full-screen Map */}
      <View style={s.mapWrap}>
        {loading && places.length === 0 ? (
          <View style={s.loadCenter}>
            <ActivityIndicator size="large" color="#2D6A4F" />
            <Text style={s.loadText}>Finding places...</Text>
          </View>
        ) : Platform.OS === 'web' ? (
          <iframe
            srcDoc={mapHTML()}
            style={{ width: '100%', height: '100%', border: 'none' } as any}
            title="Map"
          />
        ) : WebView ? (
          <WebView
            ref={wvRef}
            source={{ html: mapHTML() }}
            style={{ flex: 1 }}
            onMessage={handleMsg}
            javaScriptEnabled
            domStorageEnabled
            startInLoadingState
            renderLoading={() => (
              <View style={s.loadCenter}><ActivityIndicator size="large" color="#2D6A4F" /></View>
            )}
          />
        ) : (
          <View style={s.loadCenter}>
            <Ionicons name="map-outline" size={48} color="#2D6A4F" />
            <Text style={s.loadText}>Map loading...</Text>
          </View>
        )}

        {/* Zoom controls */}
        <View style={s.zoomBtns}>
          <TouchableOpacity style={s.zoomBtn} onPress={() => wvRef.current?.injectJavaScript('map.setZoom(map.getZoom()+1);true;')}>
            <Ionicons name="add" size={20} color="#1B4332" />
          </TouchableOpacity>
          <View style={s.zoomDivider} />
          <TouchableOpacity style={s.zoomBtn} onPress={() => wvRef.current?.injectJavaScript('map.setZoom(map.getZoom()-1);true;')}>
            <Ionicons name="remove" size={20} color="#1B4332" />
          </TouchableOpacity>
        </View>
      </View>

      {/* Bottom Place Card — animated slide up */}
      <Animated.View style={[s.bottomCard, { transform: [{ translateY: cardAnim }] }]}>
        {selected && (
          <TouchableOpacity
            activeOpacity={0.9}
            onPress={() => router.push(`/place/${selected.place_id}`)}
            style={s.cardInner}
          >
            {/* Drag Handle */}
            <View style={s.dragHandle} />

            <View style={s.cardRow}>
              {selected.photo_url ? (
                <Image source={{ uri: selected.photo_url }} style={s.cardImg} />
              ) : (
                <View style={[s.cardImg, s.cardImgFallback]}>
                  <Ionicons name="image-outline" size={28} color="#A8A29E" />
                </View>
              )}
              <View style={s.cardInfo}>
                <Text style={s.cardName} numberOfLines={1}>{selected.name}</Text>
                <View style={s.cardMeta}>
                  <View style={s.ratingPill}>
                    <Ionicons name="star" size={12} color="#FCD34D" />
                    <Text style={s.ratingText}>{selected.rating?.toFixed(1) || '—'}</Text>
                  </View>
                  <View style={[s.statusPill, { backgroundColor: selected.open_now !== false ? '#DCFCE7' : '#FEE2E2' }]}>
                    <View style={[s.statusDot, { backgroundColor: selected.open_now !== false ? '#16A34A' : '#DC2626' }]} />
                    <Text style={[s.statusLabel, { color: selected.open_now !== false ? '#16A34A' : '#DC2626' }]}>
                      {selected.open_now !== false ? 'Open' : 'Closed'}
                    </Text>
                  </View>
                  {selected.user_ratings_total && (
                    <Text style={s.reviewCount}>({selected.user_ratings_total})</Text>
                  )}
                </View>
                {selected.vicinity && (
                  <Text style={s.cardAddress} numberOfLines={1}>{selected.vicinity}</Text>
                )}
              </View>
            </View>

            <View style={s.cardActions}>
              <TouchableOpacity style={s.actionPrimary} onPress={() => openNav(selected)}>
                <Ionicons name="navigate" size={16} color="#FFF" />
                <Text style={s.actionPrimaryText}>Directions</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={s.actionSecondary}
                onPress={() => router.push({
                  pathname: '/checkin-post',
                  params: { placeId: selected.place_id, placeName: selected.name, placeLat: String(selected.lat), placeLng: String(selected.lng) },
                } as any)}
              >
                <Ionicons name="location" size={16} color="#2D6A4F" />
                <Text style={s.actionSecondaryText}>Check In</Text>
              </TouchableOpacity>
              <TouchableOpacity style={s.actionSecondary} onPress={() => router.push(`/place/${selected.place_id}`)}>
                <Ionicons name="information-circle" size={16} color="#2D6A4F" />
                <Text style={s.actionSecondaryText}>Details</Text>
              </TouchableOpacity>
            </View>
          </TouchableOpacity>
        )}
      </Animated.View>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F5F0EB' },
  // Header
  header: {
    flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 10,
    backgroundColor: '#FFFFFF', borderBottomWidth: 1, borderBottomColor: '#E8E0D5', gap: 12, zIndex: 10,
  },
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#F5F0EB', justifyContent: 'center', alignItems: 'center' },
  cityName: { fontSize: 20, fontWeight: '800', color: '#1B4332', letterSpacing: -0.5 },
  subtitle: { fontSize: 12, color: '#8B7355', marginTop: 1, fontWeight: '500' },
  locateBtn: {
    width: 40, height: 40, borderRadius: 20, backgroundColor: '#E8F5E9',
    justifyContent: 'center', alignItems: 'center', borderWidth: 1, borderColor: '#A5D6A7',
  },
  // Chips
  chipBar: { backgroundColor: '#FFFFFF', paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#E8E0D5', zIndex: 10 },
  chip: {
    flexDirection: 'row', alignItems: 'center', gap: 6,
    paddingHorizontal: 14, paddingVertical: 8, borderRadius: 20,
    backgroundColor: '#F5F0EB', borderWidth: 1.5, borderColor: '#E0D5C5',
  },
  chipActive: { backgroundColor: '#2D6A4F', borderColor: '#2D6A4F' },
  chipText: { fontSize: 13, fontWeight: '600', color: '#5C4033' },
  chipTextActive: { color: '#FFFFFF' },
  // Map
  mapWrap: { flex: 1, position: 'relative' },
  loadCenter: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#F5F0EB' },
  loadText: { marginTop: 10, fontSize: 14, color: '#8B7355', fontWeight: '500' },
  // Zoom
  zoomBtns: {
    position: 'absolute', right: 16, top: 16,
    backgroundColor: '#FFFFFF', borderRadius: 14, overflow: 'hidden',
    ...Platform.select({ ios: { shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.12, shadowRadius: 6 }, android: { elevation: 4 }, default: {} }),
  },
  zoomBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  zoomDivider: { height: 1, backgroundColor: '#E8E0D5', marginHorizontal: 8 },
  // Bottom Card
  bottomCard: {
    position: 'absolute', bottom: 0, left: 0, right: 0,
    backgroundColor: '#FFFFFF', borderTopLeftRadius: 24, borderTopRightRadius: 24,
    paddingBottom: Platform.OS === 'ios' ? 34 : 16,
    ...Platform.select({ ios: { shadowColor: '#000', shadowOffset: { width: 0, height: -4 }, shadowOpacity: 0.1, shadowRadius: 12 }, android: { elevation: 12 }, default: {} }),
  },
  cardInner: { padding: 16 },
  dragHandle: {
    width: 36, height: 4, borderRadius: 2, backgroundColor: '#D4C8B8',
    alignSelf: 'center', marginBottom: 14,
  },
  cardRow: { flexDirection: 'row', gap: 14 },
  cardImg: { width: 72, height: 72, borderRadius: 16, overflow: 'hidden' },
  cardImgFallback: { backgroundColor: '#F5F0EB', justifyContent: 'center', alignItems: 'center' },
  cardInfo: { flex: 1, justifyContent: 'center' },
  cardName: { fontSize: 18, fontWeight: '800', color: '#1B4332', letterSpacing: -0.3 },
  cardMeta: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: 6 },
  ratingPill: {
    flexDirection: 'row', alignItems: 'center', gap: 3,
    paddingHorizontal: 8, paddingVertical: 3, borderRadius: 10, backgroundColor: '#FEF3C7',
  },
  ratingText: { fontSize: 13, fontWeight: '700', color: '#92400E' },
  statusPill: {
    flexDirection: 'row', alignItems: 'center', gap: 4,
    paddingHorizontal: 8, paddingVertical: 3, borderRadius: 10,
  },
  statusDot: { width: 6, height: 6, borderRadius: 3 },
  statusLabel: { fontSize: 12, fontWeight: '700' },
  reviewCount: { fontSize: 12, color: '#8B7355' },
  cardAddress: { fontSize: 13, color: '#8B7355', marginTop: 4 },
  // Actions
  cardActions: { flexDirection: 'row', gap: 10, marginTop: 16 },
  actionPrimary: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6,
    paddingVertical: 12, borderRadius: 16, backgroundColor: '#2D6A4F',
  },
  actionPrimaryText: { fontSize: 14, fontWeight: '700', color: '#FFFFFF' },
  actionSecondary: {
    flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 5,
    paddingVertical: 12, borderRadius: 16, backgroundColor: '#E8F5E9', borderWidth: 1, borderColor: '#A5D6A7',
  },
  actionSecondaryText: { fontSize: 13, fontWeight: '700', color: '#2D6A4F' },
});
