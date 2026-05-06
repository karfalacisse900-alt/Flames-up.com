import React, { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Animated,
  Dimensions,
  Image,
  KeyboardAvoidingView,
  Platform,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { ResizeMode, Video } from 'expo-av';

import api from '../src/api/client';
import { useAuthStore } from '../src/store/authStore';
import { requireVerifiedPhone } from '../src/utils/phoneVerification';

const { width: W, height: H } = Dimensions.get('window');
const PROGRESS_DURATION = 6500;

function isVideoStatus(status: any) {
  return status?.media_type === 'video' || /\.(mp4|mov|m4v|webm)(\?.*)?$/i.test(String(status?.image || ''));
}

function statusLocation(status: any) {
  return status?.location || status?.place_name || status?.city || '';
}

export default function StoryViewerScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { user } = useAuthStore();
  const { userId } = useLocalSearchParams<{ userId: string }>();
  const [statuses, setStatuses] = useState<any[]>([]);
  const [currentIdx, setCurrentIdx] = useState(0);
  const [userInfo, setUserInfo] = useState<any>(null);
  const [reply, setReply] = useState('');
  const [sending, setSending] = useState(false);
  const [liked, setLiked] = useState(false);
  const progress = useRef(new Animated.Value(0)).current;
  const statusesRef = useRef<any[]>([]);

  useEffect(() => {
    loadStatuses();
    return () => {
      progress.stopAnimation();
    };
  }, []);

  const loadStatuses = async () => {
    try {
      const res = await api.get('/statuses');
      const allStatuses = Array.isArray(res.data) ? res.data : [];
      const group = allStatuses.find((item: any) => item.user_id === userId);
      if (!group?.statuses?.length) {
        router.back();
        return;
      }

      statusesRef.current = group.statuses;
      setStatuses(group.statuses);
      setUserInfo(group);
      startProgress(0);

      for (const status of group.statuses) {
        try { await api.post(`/statuses/${status.id}/view`); } catch {}
      }
    } catch {
      router.back();
    }
  };

  const startProgress = (idx: number) => {
    progress.stopAnimation();
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
    if (idx < items.length - 1) {
      setCurrentIdx(idx + 1);
      setLiked(false);
      startProgress(idx + 1);
    } else {
      router.back();
    }
  };

  const goPrev = () => {
    if (currentIdx > 0) {
      setCurrentIdx(currentIdx - 1);
      setLiked(false);
      startProgress(currentIdx - 1);
    }
  };

  const sendReply = async () => {
    const message = reply.trim();
    if (!message || !userInfo?.user_id) return;
    if (!requireVerifiedPhone(user, router, 'reply to stories')) return;
    setSending(true);
    try {
      await api.post('/messages', {
        receiver_id: userInfo.user_id,
        content: message,
      });
      setReply('');
      Alert.alert('Sent', 'Your message was sent.');
    } catch (error: any) {
      Alert.alert('Could not send', error?.response?.data?.detail || 'Try again in a moment.');
    } finally {
      setSending(false);
    }
  };

  if (statuses.length === 0) {
    return (
      <View style={s.loading}>
        <ActivityIndicator color="#FFFFFF" />
      </View>
    );
  }

  const current = statuses[currentIdx];
  const isOwnStory = userInfo?.user_id === user?.id;
  const location = statusLocation(current);
  const accent = current?.background_color || '#F25DBB';

  return (
    <KeyboardAvoidingView
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      style={s.container}
    >
      <StatusBar barStyle="light-content" />

      {current?.image ? (
        isVideoStatus(current) ? (
          <Video
            source={{ uri: current.image }}
            style={s.bgMedia}
            resizeMode={ResizeMode.COVER}
            shouldPlay
            isLooping
          />
        ) : (
          <Image source={{ uri: current.image }} style={s.bgMedia} />
        )
      ) : (
        <View style={[s.colorStory, { backgroundColor: accent }]} />
      )}

      <View style={s.dim} />
      <View pointerEvents="none" style={[s.shapeA, { backgroundColor: accent }]} />
      <View pointerEvents="none" style={[s.shapeB, { backgroundColor: accent }]} />
      <View pointerEvents="none" style={[s.shapeC, { backgroundColor: accent }]} />

      <View style={[s.progressRow, { top: insets.top + 10 }]}>
        {statuses.map((_, index) => (
          <View key={index} style={s.progressTrack}>
            <Animated.View
              style={[
                s.progressFill,
                index < currentIdx ? { width: '100%' } :
                index === currentIdx ? {
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

      <View style={[s.header, { top: insets.top + 24 }]}>
        <View style={s.identity}>
          <View style={s.avatar}>
            {userInfo?.user_profile_image ? (
              <Image source={{ uri: userInfo.user_profile_image }} style={s.avatarImage} />
            ) : (
              <Text style={s.avatarText}>{(userInfo?.user_full_name || userInfo?.user_username || 'U')[0]}</Text>
            )}
          </View>
          <View style={s.identityCopy}>
            <Text style={s.userName} numberOfLines={1}>{userInfo?.user_full_name || userInfo?.user_username || 'Story'}</Text>
            <Text style={s.timeLabel}>new story</Text>
          </View>
        </View>
        <TouchableOpacity style={s.closeBtn} onPress={() => router.back()}>
          <Ionicons name="close" size={24} color="#FFFFFF" />
        </TouchableOpacity>
      </View>

      <View style={s.tapLayer}>
        <TouchableOpacity style={s.tapLeft} activeOpacity={1} onPress={goPrev} />
        <TouchableOpacity style={s.tapRight} activeOpacity={1} onPress={() => goNext(currentIdx)} />
      </View>

      {current?.content ? (
        <View style={s.stickerWrap}>
          <Text style={s.stickerText}>{current.content}</Text>
        </View>
      ) : null}

      <View style={[s.caption, { bottom: Math.max(92, insets.bottom + 86) }]}>
        <Text style={s.captionTitle}>{userInfo?.user_full_name || userInfo?.user_username || 'Story'}</Text>
        {location ? <Text style={s.captionSub}>{location}</Text> : null}
      </View>

      <View style={[s.replyBar, { paddingBottom: Math.max(14, insets.bottom + 8) }]}>
        <View style={s.replyInputWrap}>
          <TextInput
            value={reply}
            onChangeText={setReply}
            editable={!isOwnStory && !sending}
            placeholder={isOwnStory ? 'This is your story' : 'Send a message'}
            placeholderTextColor="rgba(255,255,255,0.78)"
            style={s.replyInput}
          />
        </View>
        <TouchableOpacity
          style={s.replyIcon}
          disabled={isOwnStory || sending || !reply.trim()}
          onPress={sendReply}
        >
          {sending ? (
            <ActivityIndicator size="small" color="#FFFFFF" />
          ) : (
            <Ionicons name="paper-plane-outline" size={24} color="#FFFFFF" />
          )}
        </TouchableOpacity>
        <TouchableOpacity style={[s.replyIcon, liked && s.replyIconLiked]} onPress={() => setLiked((value) => !value)}>
          <Ionicons name={liked ? 'heart' : 'heart-outline'} size={24} color="#FFFFFF" />
        </TouchableOpacity>
      </View>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#000000' },
  loading: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#000000' },
  bgMedia: { ...StyleSheet.absoluteFillObject, width: W, height: H, resizeMode: 'cover' },
  colorStory: { ...StyleSheet.absoluteFillObject },
  dim: { ...StyleSheet.absoluteFillObject, backgroundColor: 'rgba(0,0,0,0.24)' },
  shapeA: { position: 'absolute', width: W * 0.8, height: 86, top: 78, left: -W * 0.25, transform: [{ rotate: '-16deg' }], borderRadius: 42 },
  shapeB: { position: 'absolute', width: W * 0.64, height: 70, top: H * 0.36, right: -W * 0.2, transform: [{ rotate: '-13deg' }], borderRadius: 35 },
  shapeC: { position: 'absolute', width: W * 0.9, height: 78, bottom: 128, left: -W * 0.16, transform: [{ rotate: '-8deg' }], borderRadius: 38 },
  progressRow: { position: 'absolute', left: 14, right: 14, zIndex: 20, flexDirection: 'row', gap: 5 },
  progressTrack: { flex: 1, height: 3, borderRadius: 3, overflow: 'hidden', backgroundColor: 'rgba(255,255,255,0.32)' },
  progressFill: { height: '100%', borderRadius: 3, backgroundColor: '#FFFFFF' },
  header: { position: 'absolute', left: 18, right: 12, zIndex: 20, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  identity: { flexDirection: 'row', alignItems: 'center', gap: 10, flex: 1 },
  avatar: { width: 38, height: 38, borderRadius: 19, overflow: 'hidden', backgroundColor: '#111111', alignItems: 'center', justifyContent: 'center', borderWidth: 1.5, borderColor: 'rgba(255,255,255,0.52)' },
  avatarImage: { width: '100%', height: '100%' },
  avatarText: { color: '#FFFFFF', fontSize: 14, fontWeight: '900' },
  identityCopy: { minWidth: 0, flex: 1 },
  userName: { color: '#FFFFFF', fontSize: 15, fontWeight: '900' },
  timeLabel: { color: 'rgba(255,255,255,0.78)', fontSize: 12, fontWeight: '700', marginTop: 1 },
  closeBtn: { width: 44, height: 44, borderRadius: 22, alignItems: 'center', justifyContent: 'center' },
  tapLayer: { ...StyleSheet.absoluteFillObject, zIndex: 8, flexDirection: 'row' },
  tapLeft: { flex: 1 },
  tapRight: { flex: 2 },
  stickerWrap: { position: 'absolute', zIndex: 18, top: H * 0.34, right: 28, maxWidth: W * 0.62, paddingHorizontal: 14, paddingVertical: 8, borderRadius: 7, backgroundColor: '#FFFFFF', transform: [{ rotate: '-8deg' }] },
  stickerText: { color: '#111111', fontSize: 15, lineHeight: 20, fontWeight: '900' },
  caption: { position: 'absolute', zIndex: 18, left: 24, right: 24 },
  captionTitle: { color: '#FFFFFF', fontSize: 18, lineHeight: 22, fontWeight: '900' },
  captionSub: { color: 'rgba(255,255,255,0.82)', fontSize: 13, lineHeight: 17, fontWeight: '700', marginTop: 2 },
  replyBar: { position: 'absolute', zIndex: 20, left: 18, right: 18, bottom: 0, flexDirection: 'row', alignItems: 'center', gap: 10 },
  replyInputWrap: { flex: 1, minHeight: 48, borderRadius: 24, borderWidth: 1.4, borderColor: 'rgba(255,255,255,0.82)', justifyContent: 'center', paddingHorizontal: 18, backgroundColor: 'rgba(0,0,0,0.16)' },
  replyInput: { color: '#FFFFFF', fontSize: 15, fontWeight: '700', paddingVertical: 0 },
  replyIcon: { width: 46, height: 46, borderRadius: 23, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(0,0,0,0.22)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.2)' },
  replyIconLiked: { backgroundColor: 'rgba(255,49,88,0.72)' },
});
