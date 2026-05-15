import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { Audio } from 'expo-av';
import { LinearGradient } from 'expo-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { colors as appColors, hitSlop, layout } from '../utils/theme';
import OptimizedImage from './OptimizedImage';
import {
  AiMusicPost,
  reportAiMusicPost,
  toggleAiMusicInteraction,
} from '../utils/aiMusic';

type Props = {
  post: AiMusicPost;
  compact?: boolean;
  onChanged?: (post: AiMusicPost) => void;
};

const moodColors: Record<string, [string, string]> = {
  chill: ['#E7F4D8', '#B4D8C0'],
  sad: ['#D8E4F6', '#B6BDD8'],
  love: ['#F8D1DA', '#DCA7B7'],
  hype: ['#20361F', '#A96F42'],
  dreamy: ['#E7D8FF', '#BFE9F2'],
  motivational: ['#F6E2A8', '#BFE2BE'],
  'late night': ['#1E2C2A', '#3A4E72'],
  soft: ['#F7E9DB', '#E9C7BF'],
  cinematic: ['#D8D2C4', '#716A5C'],
  spiritual: ['#E5F0D7', '#D7C2EF'],
  'afro vibe': ['#FFE2A6', '#B7D276'],
  'rap vibe': ['#2A2A2A', '#737373'],
};

function compactNumber(value: number) {
  if (value >= 1000000) return `${(value / 1000000).toFixed(1).replace(/\.0$/, '')}M`;
  if (value >= 1000) return `${(value / 1000).toFixed(1).replace(/\.0$/, '')}K`;
  return String(Math.max(0, Math.round(value)));
}

function lyricLines(post: AiMusicPost) {
  return String(post.lyrics_text || post.prompt_text || '')
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(0, 4);
}

export default function AiMusicCard({ post, compact = false, onChanged }: Props) {
  const router = useRouter();
  const soundRef = useRef<Audio.Sound | null>(null);
  const [playing, setPlaying] = useState(false);
  const [loading, setLoading] = useState(false);
  const [progress, setProgress] = useState(0);
  const lines = useMemo(() => lyricLines(post), [post]);
  const colors = moodColors[post.mood] || moodColors.chill;
  const waveform = post.waveform_data.length ? post.waveform_data : [0.3, 0.7, 0.45, 0.9, 0.5, 0.75, 0.35, 0.62];

  const stopAudio = async () => {
    const sound = soundRef.current;
    soundRef.current = null;
    setPlaying(false);
    setProgress(0);
    if (sound) {
      await sound.stopAsync().catch(() => undefined);
      await sound.unloadAsync().catch(() => undefined);
    }
  };

  useEffect(() => () => {
    void stopAudio();
  }, []);

  const play = async () => {
    if (!post.audio_url) {
      Alert.alert('Audio unavailable', 'This music post does not have audio yet.');
      return;
    }
    if (playing) {
      await stopAudio();
      return;
    }
    setLoading(true);
    try {
      await stopAudio();
      await Audio.setAudioModeAsync({ playsInSilentModeIOS: true }).catch(() => undefined);
      const { sound } = await Audio.Sound.createAsync(
        { uri: post.audio_url },
        { shouldPlay: true, volume: 1 }
      );
      sound.setOnPlaybackStatusUpdate((status: any) => {
        if (!status?.isLoaded) return;
        const duration = status.durationMillis || post.audio_duration * 1000 || 1;
        setProgress(Math.min(1, Math.max(0, (status.positionMillis || 0) / duration)));
        if (status.didJustFinish) {
          void stopAudio();
        }
      });
      soundRef.current = sound;
      setPlaying(true);
    } catch (error: any) {
      Alert.alert('Playback failed', error?.message || 'Could not play this music post.');
    } finally {
      setLoading(false);
    }
  };

  const interact = async (kind: 'like' | 'save' | 'repost' | 'use_sound') => {
    try {
      const result = await toggleAiMusicInteraction(post.id, kind);
      if (kind === 'use_sound') {
        router.push({
          pathname: '/create-music-post',
          params: {
            seed_music_id: post.id,
            mood: post.mood,
            style: post.style,
          },
        } as any);
        return;
      }
      const countKey = kind === 'like' ? 'likes_count' : kind === 'save' ? 'saves_count' : 'reposts_count';
      const activeKey = kind === 'like' ? 'liked' : kind === 'save' ? 'saved' : 'reposted';
      onChanged?.({
        ...post,
        [activeKey]: result.active,
        [countKey]: Math.max(0, Number((post as any)[countKey] || 0) + (result.active ? 1 : -1)),
      } as AiMusicPost);
    } catch (error: any) {
      Alert.alert('Not saved', error?.response?.data?.detail || 'Try again in a moment.');
    }
  };

  const report = async () => {
    Alert.alert('Report sound?', 'This sends the generated audio to moderation.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Report',
        style: 'destructive',
        onPress: async () => {
          try {
            await reportAiMusicPost(post.id);
            Alert.alert('Reported', 'Thanks. Moderation will review it.');
          } catch (error: any) {
            Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this sound.');
          }
        },
      },
    ]);
  };

  return (
    <TouchableOpacity activeOpacity={0.9} style={[styles.wrap, compact && styles.wrapCompact]} onPress={() => router.push(`/music-post/${post.id}` as any)}>
      <LinearGradient colors={colors} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.gradient}>
        <View style={styles.topRow}>
          <View style={styles.userRow}>
            {post.user?.profile_image ? (
              <OptimizedImage uri={post.user.profile_image} preset="avatar" style={styles.avatar} />
            ) : (
              <View style={styles.avatarFallback}>
                <Text style={styles.avatarText}>{(post.user?.full_name || post.user?.username || 'F')[0].toUpperCase()}</Text>
              </View>
            )}
            <View style={{ flex: 1, minWidth: 0 }}>
              <Text style={styles.name} numberOfLines={1}>{post.user?.full_name || post.user?.username || 'Flames creator'}</Text>
              <Text style={styles.moodText} numberOfLines={1}>{post.mood} · {post.style}</Text>
            </View>
          </View>
          <TouchableOpacity style={styles.iconButton} onPress={report} accessibilityRole="button" accessibilityLabel="Report sound" hitSlop={hitSlop}>
            <Ionicons name="flag-outline" size={18} color={appColors.textPrimary} />
          </TouchableOpacity>
        </View>

        <View style={styles.lyricsBlock}>
          {lines.length ? lines.map((line, index) => (
            <Text key={`${line}-${index}`} style={[styles.lyric, index > 1 && compact ? styles.lyricDim : null]} numberOfLines={2}>
              {line}
            </Text>
          )) : (
            <Text style={styles.lyric}>Original AI music post</Text>
          )}
        </View>

        <View style={styles.playerRow}>
          <TouchableOpacity style={styles.playButton} onPress={play} activeOpacity={0.85}>
            {loading ? (
              <ActivityIndicator color={appColors.textInverse} />
            ) : (
              <Ionicons name={playing ? 'pause' : 'play'} size={19} color={appColors.textInverse} />
            )}
          </TouchableOpacity>
          <View style={styles.waveWrap}>
            {waveform.slice(0, compact ? 30 : 42).map((bar, index) => {
              const active = index / Math.max(1, waveform.length - 1) <= progress;
              return (
                <View
                  key={`${bar}-${index}`}
                  style={[
                    styles.waveBar,
                    {
                      height: 8 + Math.round(Number(bar || 0.4) * 30),
                      backgroundColor: active || playing ? '#111111' : 'rgba(17,17,17,0.26)',
                    },
                  ]}
                />
              );
            })}
          </View>
          <Text style={styles.duration}>{Math.round(post.audio_duration || 20)}s</Text>
        </View>

        <View style={styles.actions}>
          <TouchableOpacity style={styles.actionPill} onPress={() => interact('like')}>
            <Ionicons name={post.liked ? 'heart' : 'heart-outline'} size={16} color="#111111" />
            <Text style={styles.actionText}>{compactNumber(post.likes_count)}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.actionPill} onPress={() => router.push(`/music-post/${post.id}` as any)}>
            <Ionicons name="chatbubble-outline" size={15} color="#111111" />
            <Text style={styles.actionText}>{compactNumber(post.comments_count)}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={[styles.actionPill, post.saved && styles.actionPillOn]} onPress={() => interact('save')}>
            <Ionicons name={post.saved ? 'bookmark' : 'bookmark-outline'} size={14} color={post.saved ? appColors.textInverse : '#111111'} />
            <Text style={[styles.actionText, post.saved && styles.actionTextOn]}>{compactNumber(post.saves_count)}</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.useSound} onPress={() => interact('use_sound')}>
            <Ionicons name="musical-notes" size={14} color={appColors.textInverse} />
            <Text style={styles.useSoundText}>Use sound</Text>
          </TouchableOpacity>
        </View>
      </LinearGradient>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  wrap: { borderRadius: 22, overflow: 'hidden', backgroundColor: appColors.bgSubtle, borderWidth: 1, borderColor: 'rgba(22,24,19,0.08)' },
  wrapCompact: { marginBottom: 14 },
  gradient: { minHeight: 264, padding: 16, justifyContent: 'space-between', gap: 14 },
  topRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10 },
  userRow: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 10 },
  avatar: { width: 40, height: 40, borderRadius: 20, backgroundColor: appColors.surfaceRaised },
  avatarFallback: { width: 40, height: 40, borderRadius: 20, backgroundColor: appColors.textPrimary, alignItems: 'center', justifyContent: 'center' },
  avatarText: { color: appColors.textInverse, fontSize: 14, fontWeight: '500' },
  name: { color: appColors.textPrimary, fontSize: 14, fontWeight: '600' },
  moodText: { color: 'rgba(22,24,19,0.64)', fontSize: 11, fontWeight: '500', marginTop: 2, textTransform: 'capitalize' },
  iconButton: { width: layout.minTouchTarget, height: layout.minTouchTarget, borderRadius: 22, backgroundColor: 'rgba(255,255,255,0.58)', alignItems: 'center', justifyContent: 'center' },
  lyricsBlock: { minHeight: 96, justifyContent: 'center', gap: 6 },
  lyric: { color: appColors.textPrimary, fontSize: 21, lineHeight: 27, fontWeight: '500' },
  lyricDim: { opacity: 0.68 },
  playerRow: { minHeight: 48, borderRadius: 24, backgroundColor: 'rgba(255,255,255,0.62)', flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 8 },
  playButton: { width: 38, height: 38, borderRadius: 19, backgroundColor: appColors.accentPrimary, borderWidth: 1, borderColor: appColors.accentPrimaryHover, alignItems: 'center', justifyContent: 'center' },
  waveWrap: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 2, height: 42, overflow: 'hidden' },
  waveBar: { width: 3, borderRadius: 2 },
  duration: { color: '#111111', fontSize: 11, fontWeight: '500', fontVariant: ['tabular-nums'] },
  actions: { flexDirection: 'row', alignItems: 'center', gap: 8, flexWrap: 'wrap' },
  actionPill: { minHeight: 32, borderRadius: 16, backgroundColor: 'rgba(255,255,255,0.54)', flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 9 },
  actionPillOn: { backgroundColor: appColors.accentPrimary, borderWidth: 1, borderColor: appColors.accentPrimaryHover },
  actionText: { color: appColors.textPrimary, fontSize: 11, fontWeight: '500' },
  actionTextOn: { color: appColors.textInverse },
  useSound: { minHeight: 36, borderRadius: 18, backgroundColor: appColors.textPrimary, flexDirection: 'row', alignItems: 'center', gap: 6, paddingHorizontal: 12 },
  useSoundText: { color: appColors.textInverse, fontSize: 11, fontWeight: '500' },
});
