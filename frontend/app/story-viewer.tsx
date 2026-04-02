import React, { useState, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Image,
  TouchableOpacity,
  Dimensions,
  Animated,
  StatusBar,
} from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { Video, ResizeMode } from 'expo-av';
import { colors } from '../src/utils/theme';
import api from '../src/api/client';

const { width: W, height: H } = Dimensions.get('window');
const PROGRESS_DURATION = 5000;

export default function StoryViewerScreen() {
  const router = useRouter();
  const { userId } = useLocalSearchParams<{ userId: string }>();
  const [statuses, setStatuses] = useState<any[]>([]);
  const [currentIdx, setCurrentIdx] = useState(0);
  const [userInfo, setUserInfo] = useState<any>(null);
  const progress = useRef(new Animated.Value(0)).current;
  const timerRef = useRef<any>(null);
  const statusesRef = useRef<any[]>([]);

  useEffect(() => {
    loadStatuses();
    return () => {
      if (timerRef.current) clearTimeout(timerRef.current);
      progress.stopAnimation();
    };
  }, []);

  const loadStatuses = async () => {
    try {
      const res = await api.get('/statuses');
      const allStatuses = Array.isArray(res.data) ? res.data : [];
      const userGroup = allStatuses.find((g: any) => g.user_id === userId);
      if (userGroup && Array.isArray(userGroup.statuses) && userGroup.statuses.length > 0) {
        statusesRef.current = userGroup.statuses;
        setStatuses(userGroup.statuses);
        setUserInfo(userGroup);
        startProgress(0);
        // Mark as viewed
        for (const s of userGroup.statuses) {
          try { await api.post(`/statuses/${s.id}/view`); } catch {}
        }
      } else {
        router.back();
      }
    } catch (error) {
      console.log('Error loading statuses:', error);
      router.back();
    }
  };

  const startProgress = (idx: number) => {
    progress.setValue(0);
    Animated.timing(progress, {
      toValue: 1,
      duration: PROGRESS_DURATION,
      useNativeDriver: false,
    }).start(({ finished }) => {
      if (finished) goNext(idx);
    });
  };

  const goNext = (idx: number) => {
    const items = statusesRef.current;
    if (!items || items.length === 0) {
      router.back();
      return;
    }
    if (idx < items.length - 1) {
      setCurrentIdx(idx + 1);
      startProgress(idx + 1);
    } else {
      router.back();
    }
  };

  const goPrev = () => {
    if (currentIdx > 0) {
      setCurrentIdx(currentIdx - 1);
      startProgress(currentIdx - 1);
    }
  };

  const handleTap = (side: 'left' | 'right') => {
    if (side === 'right') goNext(currentIdx);
    else goPrev();
  };

  if (statuses.length === 0) return <View style={s.container} />;
  const current = statuses[currentIdx];

  return (
    <View style={s.container}>
      <StatusBar barStyle="light-content" />

      {/* Background */}
      {current?.media_type === 'video' && current?.image ? (
        <Video
          source={{ uri: current.image }}
          style={s.bgImage}
          resizeMode={ResizeMode.COVER}
          shouldPlay
          isLooping
          isMuted={false}
        />
      ) : current?.image ? (
        <Image source={{ uri: current.image }} style={s.bgImage} />
      ) : (
        <View style={[s.bgColor, { backgroundColor: current?.background_color || '#6366f1' }]} />
      )}

      {/* Dark overlay */}
      <View style={s.overlay} />

      {/* Progress bars */}
      <View style={s.progressRow}>
        {statuses.map((_, i) => (
          <View key={i} style={s.progressBg}>
            <Animated.View
              style={[
                s.progressFill,
                i < currentIdx ? { width: '100%' } :
                i === currentIdx ? {
                  width: progress.interpolate({
                    inputRange: [0, 1],
                    outputRange: ['0%', '100%'],
                  }),
                } : { width: 0 },
              ]}
            />
          </View>
        ))}
      </View>

      {/* Header */}
      <View style={s.header}>
        <View style={s.headerLeft}>
          <View style={s.avatar}>
            {userInfo?.user_profile_image ? (
              <Image source={{ uri: userInfo.user_profile_image }} style={{ width: '100%', height: '100%' }} />
            ) : (
              <Text style={s.avatarText}>{(userInfo?.user_full_name || 'U')[0]}</Text>
            )}
          </View>
          <Text style={s.userName}>{userInfo?.user_full_name || 'User'}</Text>
          <Text style={s.timeLabel}>now</Text>
        </View>
        <TouchableOpacity onPress={() => router.back()} style={s.closeBtn}>
          <Ionicons name="close" size={24} color="#FFFFFF" />
        </TouchableOpacity>
      </View>

      {/* Content text */}
      {current?.content && (
        <View style={s.contentWrap}>
          <Text style={s.contentText}>{current.content}</Text>
        </View>
      )}

      {/* Tap areas */}
      <View style={s.tapAreas}>
        <TouchableOpacity style={s.tapLeft} onPress={() => handleTap('left')} activeOpacity={1} />
        <TouchableOpacity style={s.tapRight} onPress={() => handleTap('right')} activeOpacity={1} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000000' },
  bgImage: { ...StyleSheet.absoluteFillObject, width: W, height: H, resizeMode: 'cover' },
  bgColor: { ...StyleSheet.absoluteFillObject },
  overlay: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.15)' },
  progressRow: { flexDirection: 'row', gap: 3, paddingHorizontal: 8, paddingTop: 50, zIndex: 10 },
  progressBg: { flex: 1, height: 2.5, backgroundColor: 'rgba(255,255,255,0.3)', borderRadius: 2, overflow: 'hidden' },
  progressFill: { height: '100%', backgroundColor: '#FFFFFF', borderRadius: 2 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 12, paddingTop: 12, zIndex: 10 },
  headerLeft: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  avatar: { width: 36, height: 36, borderRadius: 18, overflow: 'hidden', backgroundColor: 'rgba(255,255,255,0.2)', justifyContent: 'center', alignItems: 'center' },
  avatarText: { color: '#FFFFFF', fontSize: 14, fontWeight: '700' },
  userName: { color: '#FFFFFF', fontSize: 15, fontWeight: '700' },
  timeLabel: { color: 'rgba(255,255,255,0.7)', fontSize: 13 },
  closeBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  contentWrap: { position: 'absolute', bottom: 120, left: 0, right: 0, alignItems: 'center', zIndex: 10, paddingHorizontal: 24 },
  contentText: { color: '#FFFFFF', fontSize: 22, fontWeight: '700', textAlign: 'center', lineHeight: 30, textShadowColor: 'rgba(0,0,0,0.5)', textShadowOffset: { width: 0, height: 1 }, textShadowRadius: 4 },
  tapAreas: { ...StyleSheet.absoluteFillObject, flexDirection: 'row', zIndex: 5 },
  tapLeft: { flex: 1 },
  tapRight: { flex: 2 },
});
