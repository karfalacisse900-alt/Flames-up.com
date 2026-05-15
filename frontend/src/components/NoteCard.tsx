import React from 'react';
import { Alert, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { NotePost, compactNumber, reportNote, toggleNoteInteraction } from '../utils/recommendFeatures';
import { colors, hitSlop, layout } from '../utils/theme';
import OptimizedImage from './OptimizedImage';

type Props = {
  note: NotePost;
  onChanged?: (note: NotePost) => void;
};

function timeLabel(value?: string) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return 'now';
  const diff = Date.now() - date.getTime();
  const minutes = Math.max(1, Math.round(diff / 60000));
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h`;
  return `${Math.round(hours / 24)}d`;
}

export default function NoteCard({ note, onChanged }: Props) {
  const router = useRouter();
  const userName = note.user?.full_name || note.user?.username || 'Anonymous';

  const interact = async (kind: 'reaction' | 'save' | 'share') => {
    try {
      const result = await toggleNoteInteraction(note.id, kind, kind === 'reaction' ? 'heart' : undefined);
      const countKey = kind === 'save' ? 'saves_count' : kind === 'share' ? 'shares_count' : 'reactions_count';
      const activeKey = kind === 'save' ? 'saved' : 'reacted';
      onChanged?.({
        ...note,
        [activeKey]: kind === 'share' ? (note as any)[activeKey] : result.active,
        [countKey]: Math.max(0, Number((note as any)[countKey] || 0) + (kind === 'share' || result.active ? 1 : -1)),
      } as NotePost);
    } catch (error: any) {
      Alert.alert('Not updated', error?.response?.data?.detail || 'Try again in a moment.');
    }
  };

  const report = () => {
    Alert.alert('Report note?', 'Moderation can see the real account even if the note is anonymous.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Report',
        style: 'destructive',
        onPress: async () => {
          try {
            await reportNote(note.id);
            Alert.alert('Reported', 'Thanks. Moderation will review it.');
          } catch (error: any) {
            Alert.alert('Report failed', error?.response?.data?.detail || 'Could not report this note.');
          }
        },
      },
    ]);
  };

  return (
    <TouchableOpacity activeOpacity={0.9} style={[styles.card, { backgroundColor: note.color || '#F6E7D7' }]} onPress={() => router.push(`/note/${note.id}` as any)}>
      <View style={styles.topRow}>
        <View style={styles.authorRow}>
          {note.user?.profile_image ? (
            <OptimizedImage uri={note.user.profile_image} preset="avatar" style={styles.avatar} />
          ) : (
            <View style={[styles.avatar, styles.avatarFallback]}>
              <Text style={styles.avatarText}>{userName[0]?.toUpperCase() || 'A'}</Text>
            </View>
          )}
          <View style={{ flex: 1, minWidth: 0 }}>
            <Text style={styles.name} numberOfLines={1}>{userName}</Text>
            <Text style={styles.meta} numberOfLines={1}>{note.note_type} · {note.mood} · {timeLabel(note.created_at)}</Text>
          </View>
        </View>
        <TouchableOpacity style={styles.iconBtn} onPress={report} accessibilityRole="button" accessibilityLabel="Report note" hitSlop={hitSlop}>
          <Ionicons name="flag-outline" size={17} color={colors.textPrimary} />
        </TouchableOpacity>
      </View>

      <Text style={styles.body}>{note.body}</Text>

      <View style={styles.actionRow}>
        <TouchableOpacity style={[styles.action, note.reacted && styles.actionOn]} onPress={() => interact('reaction')}>
          <Ionicons name={note.reacted ? 'heart' : 'heart-outline'} size={15} color={note.reacted ? colors.textInverse : '#111111'} />
          <Text style={[styles.actionText, note.reacted && styles.actionTextOn]}>{compactNumber(note.reactions_count)}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.action} onPress={() => router.push(`/note/${note.id}` as any)}>
          <Ionicons name="chatbubble-outline" size={15} color="#111111" />
          <Text style={styles.actionText}>{compactNumber(note.comments_count)}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[styles.action, note.saved && styles.actionOn]} onPress={() => interact('save')}>
          <Ionicons name={note.saved ? 'bookmark' : 'bookmark-outline'} size={14} color={note.saved ? colors.textInverse : '#111111'} />
          <Text style={[styles.actionText, note.saved && styles.actionTextOn]}>{compactNumber(note.saves_count)}</Text>
        </TouchableOpacity>
        <TouchableOpacity style={styles.action} onPress={() => interact('share')}>
          <Ionicons name="arrow-redo-outline" size={16} color="#111111" />
          <Text style={styles.actionText}>{compactNumber(note.shares_count)}</Text>
        </TouchableOpacity>
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  card: { borderRadius: 22, borderWidth: 1, borderColor: 'rgba(22,24,19,0.08)', padding: 16, gap: 16 },
  topRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 10 },
  authorRow: { flex: 1, minWidth: 0, flexDirection: 'row', alignItems: 'center', gap: 10 },
  avatar: { width: 40, height: 40, borderRadius: 20, backgroundColor: colors.surfaceRaised },
  avatarFallback: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.textPrimary },
  avatarText: { color: colors.textInverse, fontSize: 14, fontWeight: '500' },
  name: { color: colors.textPrimary, fontSize: 14, fontWeight: '600' },
  meta: { color: 'rgba(22,24,19,0.58)', fontSize: 11, fontWeight: '500', marginTop: 2, textTransform: 'capitalize' },
  iconBtn: { width: layout.minTouchTarget, height: layout.minTouchTarget, borderRadius: 22, backgroundColor: 'rgba(255,255,255,0.58)', alignItems: 'center', justifyContent: 'center' },
  body: { color: colors.textPrimary, fontSize: 22, lineHeight: 29, fontWeight: '500' },
  actionRow: { flexDirection: 'row', alignItems: 'center', flexWrap: 'wrap', gap: 8 },
  action: { minHeight: 32, borderRadius: 16, backgroundColor: 'rgba(255,255,255,0.58)', flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 9 },
  actionOn: { backgroundColor: colors.accentPrimary, borderWidth: 1, borderColor: colors.accentPrimaryHover },
  actionText: { color: colors.textPrimary, fontSize: 12, fontWeight: '500' },
  actionTextOn: { color: colors.textInverse },
});
