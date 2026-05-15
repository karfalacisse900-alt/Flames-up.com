import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Image,
  Modal,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { formatDistanceToNow } from 'date-fns';

import api from '../../src/api/client';
import SensitiveScreen from '../../src/components/SensitiveScreen';
import { useAuthStore } from '../../src/store/authStore';
import { buildAgoraCallHref } from '../../src/utils/calls';
import { requireVerifiedPhone } from '../../src/utils/phoneVerification';
import { appFontFamily } from '../../src/utils/typography';
import { borderRadius, colors, hitSlop, shadows, spacing } from '../../src/utils/theme';

type ChatProfile = {
  id: string;
  name: string;
  avatar?: string;
  subtitle?: string;
  hasStory?: boolean;
  hasUnviewed?: boolean;
};

function nameFromUser(user: any, fallback = 'Friend') {
  return user?.full_name || user?.username || fallback;
}

function initialFor(name: string) {
  return String(name || 'F').slice(0, 1).toUpperCase();
}

function formatChatTime(value: unknown) {
  const date = new Date(String(value || Date.now()));
  if (Number.isNaN(date.getTime())) return '';
  const diffMs = Date.now() - date.getTime();
  const oneDay = 24 * 60 * 60 * 1000;
  if (diffMs >= 0 && diffMs < oneDay) {
    return date.toLocaleTimeString(undefined, { hour: '2-digit', minute: '2-digit', hour12: false });
  }
  return formatDistanceToNow(date, { addSuffix: true }).replace('about ', '');
}

export default function MessagesScreen() {
  const router = useRouter();
  const user = useAuthStore((state) => state.user);
  const currentUserId = user?.id;
  const [conversations, setConversations] = useState<any[]>([]);
  const [friendStatusGroups, setFriendStatusGroups] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [showGroupComposer, setShowGroupComposer] = useState(false);
  const [groupName, setGroupName] = useState('');
  const [peopleQuery, setPeopleQuery] = useState('');
  const [people, setPeople] = useState<any[]>([]);
  const [selectedPeople, setSelectedPeople] = useState<Record<string, any>>({});
  const [isPeopleLoading, setIsPeopleLoading] = useState(false);
  const [isCreatingGroup, setIsCreatingGroup] = useState(false);

  const loadConversations = useCallback(async () => {
    try {
      const response = await api.get('/conversations');
      setConversations(Array.isArray(response.data) ? response.data : []);
    } catch (error) {
      console.log('Error loading conversations:', error);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const loadFriendStories = useCallback(async () => {
    try {
      const response = await api.get('/statuses/friends');
      const groups = Array.isArray(response.data) ? response.data : [];
      setFriendStatusGroups(groups.filter((group: any) => (
        group?.user_id
        && Array.isArray(group.statuses)
        && group.statuses.length > 0
      )));
    } catch (error) {
      console.log('Error loading friend stories:', error);
      setFriendStatusGroups([]);
    }
  }, []);

  useEffect(() => {
    loadConversations();
    loadFriendStories();
    const interval = setInterval(() => {
      loadConversations();
      loadFriendStories();
    }, 8000);
    return () => clearInterval(interval);
  }, [loadConversations, loadFriendStories]);

  const loadPeople = useCallback(async (query = '') => {
    setIsPeopleLoading(true);
    try {
      const trimmed = query.trim();
      const response = trimmed
        ? await api.get(`/users/search/${encodeURIComponent(trimmed)}`)
        : await api.get('/discover/suggested-users');
      setPeople(Array.isArray(response.data) ? response.data.filter((person: any) => person.id !== currentUserId) : []);
    } catch {
      setPeople([]);
    } finally {
      setIsPeopleLoading(false);
    }
  }, [currentUserId]);

  useEffect(() => {
    if (!showGroupComposer) return;
    const timer = setTimeout(() => {
      loadPeople(peopleQuery);
    }, 250);
    return () => clearTimeout(timer);
  }, [showGroupComposer, peopleQuery, loadPeople]);

  const storyProfiles = useMemo<ChatProfile[]>(() => (
    friendStatusGroups.map((group: any) => ({
      id: group.user_id,
      name: group.user_full_name || group.user_username || 'Friend',
      avatar: group.user_profile_image,
      hasStory: true,
      hasUnviewed: !!group.has_unviewed,
    }))
  ), [friendStatusGroups]);

  const openGroupComposer = () => {
    if (!requireVerifiedPhone(user, router, 'create group chats')) return;
    setShowGroupComposer(true);
    setGroupName('');
    setPeopleQuery('');
    setSelectedPeople({});
  };

  const togglePerson = (person: any) => {
    setSelectedPeople((prev) => {
      const next = { ...prev };
      if (next[person.id]) delete next[person.id];
      else next[person.id] = person;
      return next;
    });
  };

  const createGroupChat = async () => {
    const memberIds = Object.keys(selectedPeople);
    if (memberIds.length < 2) {
      Alert.alert('Choose people', 'Pick at least two people to create a group chat.');
      return;
    }
    if (!requireVerifiedPhone(user, router, 'create group chats')) return;

    setIsCreatingGroup(true);
    try {
      const response = await api.post('/group-chats', {
        name: groupName.trim() || 'New group',
        member_ids: memberIds,
      });
      setShowGroupComposer(false);
      await loadConversations();
      router.push(`/group-conversation/${response.data.id}` as any);
    } catch (error: any) {
      Alert.alert('Group failed', error?.response?.data?.detail || 'Could not create this group chat.');
    } finally {
      setIsCreatingGroup(false);
    }
  };

  const startVideoCall = (otherUser: any) => {
    if (!requireVerifiedPhone(user, router, 'start video calls')) return;
    router.push(buildAgoraCallHref({
      currentUserId,
      peerId: otherUser?.id,
      peerName: otherUser?.full_name || otherUser?.username || 'Video call',
      peerAvatar: otherUser?.profile_image || '',
    }) as any);
  };

  const openProfileOrChat = (profile: ChatProfile) => {
    if (profile.hasStory) {
      router.push({ pathname: '/story-viewer', params: { userId: profile.id } } as any);
      return;
    }
    router.push(`/conversation/${profile.id}` as any);
  };

  const renderAvatar = (profile: ChatProfile, size = 54) => (
    profile.avatar ? (
      <Image source={{ uri: profile.avatar }} style={{ width: size, height: size, borderRadius: size / 2 }} />
    ) : (
      <View style={[styles.avatarFallback, { width: size, height: size, borderRadius: size / 2 }]}>
        <Text style={[styles.avatarInitial, { fontSize: Math.max(17, size * 0.36) }]}>{initialFor(profile.name)}</Text>
      </View>
    )
  );

  const renderStory = (profile: ChatProfile) => (
    <TouchableOpacity key={profile.id} style={styles.storyItem} activeOpacity={0.9} onPress={() => openProfileOrChat(profile)}>
      <View style={[styles.storyRing, profile.hasUnviewed && styles.storyRingHot]}>
        {renderAvatar(profile, 54)}
      </View>
      <Text style={styles.storyName} numberOfLines={1}>{profile.name}</Text>
    </TouchableOpacity>
  );

  const renderConversation = ({ item, index }: { item: any; index: number }) => {
    if (item.type === 'group') {
      return (
        <TouchableOpacity
          style={[styles.conversationRow, index === conversations.length - 1 && styles.conversationRowLast]}
          onPress={() => router.push(`/group-conversation/${item.group_id}` as any)}
          activeOpacity={0.84}
        >
          <View style={styles.groupAvatar}>
            <Ionicons name="people" size={21} color={colors.textInverse} />
          </View>
          <View style={styles.conversationInfo}>
            <Text style={styles.userName} numberOfLines={1}>{item.group_name || 'Group chat'}</Text>
            <Text style={styles.lastMessage} numberOfLines={1}>{item.last_message || `${item.member_count || 0} members`}</Text>
          </View>
          <View style={styles.rowMeta}>
            <Text style={styles.timeText}>{formatChatTime(item.last_message_time)}</Text>
          </View>
        </TouchableOpacity>
      );
    }

    const otherUser = item.other_user || {};
    const hasUnread = item.unread_count > 0;
    const displayName = nameFromUser(otherUser);
    const isOnline = !!otherUser.is_online;
    const isTyping = !!otherUser.is_typing;

    return (
      <TouchableOpacity
        style={[styles.conversationRow, index === conversations.length - 1 && styles.conversationRowLast]}
        onPress={() => otherUser.id && router.push(`/conversation/${otherUser.id}`)}
        activeOpacity={0.84}
      >
        <View style={styles.avatarWrap}>
          {renderAvatar({ id: otherUser.id, name: displayName, avatar: otherUser.profile_image }, 48)}
          {isOnline ? <View style={styles.onlineDot} /> : null}
        </View>
        <View style={styles.conversationInfo}>
          <Text style={[styles.userName, hasUnread && styles.userNameUnread]} numberOfLines={1}>
            {displayName}
          </Text>
          <Text
            style={[styles.lastMessage, hasUnread && styles.lastMessageUnread, isTyping && styles.typingMessage]}
            numberOfLines={1}
          >
            {isTyping ? 'typing...' : item.last_message || (isOnline ? 'Online' : 'Start the chat')}
          </Text>
        </View>
        <View style={styles.rowMeta}>
          <Text style={styles.timeText}>{formatChatTime(item.last_message_time)}</Text>
          {hasUnread || !item.last_message ? (
            <View style={[styles.turnPill, !item.last_message && styles.startPill]}>
              <Text style={[styles.turnText, !item.last_message && styles.startText]}>{item.last_message ? 'Your Turn' : 'Start Chat'}</Text>
            </View>
          ) : null}
          {otherUser.id ? (
            <TouchableOpacity style={styles.callMiniButton} onPress={() => startVideoCall(otherUser)} activeOpacity={0.8} hitSlop={hitSlop}>
              <Ionicons name="videocam-outline" size={14} color={colors.textHint} />
            </TouchableOpacity>
          ) : null}
        </View>
      </TouchableOpacity>
    );
  };

  const renderHeader = () => (
    <View>
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Chat</Text>
        <View style={styles.headerActions}>
          <TouchableOpacity style={styles.headerIconButton} activeOpacity={0.82} accessibilityLabel="Filter chats" hitSlop={hitSlop}>
            <Ionicons name="funnel-outline" size={20} color={colors.textPrimary} />
          </TouchableOpacity>
          <TouchableOpacity style={styles.headerIconButton} activeOpacity={0.82} onPress={openGroupComposer} accessibilityLabel="Search or start chat" hitSlop={hitSlop}>
            <Ionicons name="search" size={20} color={colors.textPrimary} />
          </TouchableOpacity>
        </View>
      </View>

      <ScrollView horizontal showsHorizontalScrollIndicator={false} bounces={false} overScrollMode="never" contentContainerStyle={styles.storyRail}>
        {storyProfiles.length > 0 ? storyProfiles.map(renderStory) : (
          <View style={styles.emptyStoryPill}>
            <Ionicons name="people-outline" size={18} color={colors.textHint} />
            <Text style={styles.emptyStoryPillText}>Friend stories will appear here</Text>
          </View>
        )}
      </ScrollView>
    </View>
  );

  if (isLoading) {
    return (
      <SensitiveScreen label="Private chats">
        <SafeAreaView style={styles.loadingContainer}>
          <View style={styles.loadingCard}>
            <View style={styles.loadingBubbleLarge} />
            <View style={styles.loadingBubbleSmall} />
            <Text style={styles.loadingTitle}>Loading chats</Text>
          </View>
        </SafeAreaView>
      </SensitiveScreen>
    );
  }

  return (
    <SensitiveScreen label="Private chats">
      <SafeAreaView style={styles.container} edges={['top']}>
        <FlatList
          data={conversations}
          renderItem={renderConversation}
          keyExtractor={(item) => String(item.id || item.group_id)}
          ListHeaderComponent={renderHeader}
          ListEmptyComponent={
            <View style={styles.emptyContainer}>
              <Ionicons name="chatbubbles-outline" size={52} color={colors.textTertiary} />
              <Text style={styles.emptyTitle}>No chats yet</Text>
              <Text style={styles.emptyText}>Start a conversation with someone.</Text>
            </View>
          }
          showsVerticalScrollIndicator={false}
          contentContainerStyle={styles.listContent}
          bounces={false}
          alwaysBounceVertical={false}
          overScrollMode="never"
        />

        <Modal visible={showGroupComposer} transparent animationType="slide" onRequestClose={() => setShowGroupComposer(false)}>
          <View style={styles.modalOverlay}>
            <View style={styles.groupSheet}>
              <View style={styles.sheetHandle} />
              <View style={styles.groupHeader}>
                <View>
                  <Text style={styles.groupTitle}>New chat</Text>
                  <Text style={styles.groupSubtitle}>{Object.keys(selectedPeople).length} selected</Text>
                </View>
                <TouchableOpacity style={styles.closeButton} onPress={() => setShowGroupComposer(false)}>
                  <Ionicons name="close" size={20} color={colors.textPrimary} />
                </TouchableOpacity>
              </View>

              <TextInput
                style={styles.groupNameInput}
                placeholder="Group name"
                placeholderTextColor={colors.textTertiary}
                value={groupName}
                onChangeText={setGroupName}
                maxLength={80}
              />
              <TextInput
                style={styles.searchInput}
                placeholder="Search people"
                placeholderTextColor={colors.textTertiary}
                value={peopleQuery}
                onChangeText={setPeopleQuery}
                autoCapitalize="none"
              />

              {Object.values(selectedPeople).length > 0 && (
                <ScrollView horizontal showsHorizontalScrollIndicator={false} bounces={false} overScrollMode="never" contentContainerStyle={styles.selectedRail}>
                  {Object.values(selectedPeople).map((person: any) => (
                    <TouchableOpacity key={person.id} style={styles.selectedChip} onPress={() => togglePerson(person)}>
                      <Text style={styles.selectedChipText}>{person.full_name || person.username}</Text>
                      <Ionicons name="close" size={14} color={colors.textInverse} />
                    </TouchableOpacity>
                  ))}
                </ScrollView>
              )}

              {isPeopleLoading ? (
                <View style={styles.peopleLoading}>
                  <ActivityIndicator color={colors.primary} />
                </View>
              ) : (
                <FlatList
                  data={people}
                  keyExtractor={(person) => person.id}
                  style={styles.peopleList}
                  bounces={false}
                  overScrollMode="never"
                  renderItem={({ item: person }) => {
                    const selected = !!selectedPeople[person.id];
                    return (
                      <TouchableOpacity style={styles.personRow} onPress={() => togglePerson(person)}>
                        {person.profile_image ? (
                          <Image source={{ uri: person.profile_image }} style={styles.personAvatar} />
                        ) : (
                          <View style={styles.personAvatarFallback}>
                            <Text style={styles.personAvatarText}>{initialFor(person.full_name || person.username || 'F')}</Text>
                          </View>
                        )}
                        <View style={styles.personInfo}>
                          <Text style={styles.personName}>{person.full_name || person.username}</Text>
                          <Text style={styles.personHandle}>@{person.username || 'flames'}</Text>
                        </View>
                        <View style={[styles.pickCircle, selected && styles.pickCircleOn]}>
                          {selected && <Ionicons name="checkmark" size={16} color={colors.textInverse} />}
                        </View>
                      </TouchableOpacity>
                    );
                  }}
                  ListEmptyComponent={<Text style={styles.noPeopleText}>No people found</Text>}
                />
              )}

              <TouchableOpacity style={[styles.createGroupButton, isCreatingGroup && styles.createGroupButtonDisabled]} onPress={createGroupChat} disabled={isCreatingGroup}>
                {isCreatingGroup ? <ActivityIndicator color={colors.textInverse} /> : <Text style={styles.createGroupText}>Create chat</Text>}
              </TouchableOpacity>
            </View>
          </View>
        </Modal>
      </SafeAreaView>
    </SensitiveScreen>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.bgApp,
    paddingHorizontal: spacing.lg,
  },
  loadingCard: {
    width: '100%',
    maxWidth: 280,
    minHeight: 170,
    borderRadius: 30,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
    ...shadows.elevation1,
  },
  loadingBubbleLarge: {
    width: 76,
    height: 58,
    borderRadius: 29,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  loadingBubbleSmall: {
    width: 36,
    height: 28,
    borderRadius: 14,
    backgroundColor: colors.accentPrimaryLight,
    marginTop: -14,
    marginLeft: 54,
    borderWidth: 1,
    borderColor: colors.borderLight,
  },
  loadingTitle: {
    marginTop: spacing.md,
    color: colors.textSecondary,
    fontSize: 14,
    lineHeight: 18,
    fontWeight: '600',
  },
  listContent: { paddingBottom: 104 },
  header: {
    minHeight: 58,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.section,
    paddingTop: spacing.sm,
  },
  headerTitle: {
    color: colors.textPrimary,
    fontFamily: appFontFamily,
    fontSize: 24,
    lineHeight: 30,
    fontWeight: '700',
  },
  headerActions: { flexDirection: 'row', alignItems: 'center', gap: spacing.gutter },
  headerIconButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  storyRail: {
    paddingHorizontal: spacing.section,
    paddingTop: spacing.gutter,
    paddingBottom: spacing.md,
    gap: spacing.gutter,
  },
  storyItem: { width: 70, alignItems: 'center' },
  storyRing: {
    width: 62,
    height: 62,
    borderRadius: 31,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: '#F27175',
    backgroundColor: colors.surfaceRaised,
  },
  storyRingHot: { borderColor: '#FF4E61' },
  storyName: { marginTop: 7, color: colors.textHint, fontSize: 12, lineHeight: 15, fontWeight: '500', textAlign: 'center' },
  emptyStoryPill: {
    minHeight: 54,
    borderRadius: 27,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.sm,
    paddingHorizontal: spacing.md,
  },
  emptyStoryPillText: { color: colors.textHint, fontSize: 12, fontWeight: '600' },
  avatarFallback: { alignItems: 'center', justifyContent: 'center', backgroundColor: colors.accentPrimaryLight },
  avatarInitial: { color: colors.accentPrimary, fontWeight: '700' },
  conversationRow: {
    minHeight: 72,
    marginHorizontal: spacing.section,
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.borderSubtle,
  },
  conversationRowLast: { borderBottomWidth: 0 },
  avatarWrap: { width: 52, height: 52, justifyContent: 'center' },
  onlineDot: {
    position: 'absolute',
    right: 2,
    bottom: 4,
    width: 12,
    height: 12,
    borderRadius: 6,
    borderWidth: 2,
    borderColor: colors.bgApp,
    backgroundColor: '#36C56B',
  },
  groupAvatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
    backgroundColor: colors.accentPrimary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  conversationInfo: { flex: 1, minWidth: 0, paddingLeft: spacing.gutter },
  userName: { color: colors.textPrimary, fontSize: 15, lineHeight: 19, fontWeight: '700' },
  userNameUnread: { color: colors.textPrimary },
  lastMessage: { marginTop: 3, color: colors.textHint, fontSize: 13, lineHeight: 17, fontWeight: '500' },
  lastMessageUnread: { color: colors.textSecondary },
  typingMessage: { color: colors.accentPrimary, fontWeight: '700' },
  rowMeta: { minWidth: 72, alignItems: 'flex-end', gap: 5 },
  timeText: { color: colors.textHint, fontSize: 11, lineHeight: 14, fontWeight: '500' },
  turnPill: { height: 20, borderRadius: 10, backgroundColor: '#FFE8EB', alignItems: 'center', justifyContent: 'center', paddingHorizontal: 8 },
  startPill: { backgroundColor: '#FF7C86' },
  turnText: { color: '#FF6470', fontSize: 9, lineHeight: 12, fontWeight: '700' },
  startText: { color: '#FFFFFF' },
  callMiniButton: {
    width: 25,
    height: 25,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  emptyContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    marginHorizontal: spacing.section,
    marginTop: spacing.lg,
    minHeight: 160,
    borderRadius: 22,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: spacing.lg,
    ...shadows.elevation1,
  },
  emptyTitle: { marginTop: spacing.md, color: colors.textPrimary, fontSize: 18, fontWeight: '700' },
  emptyText: { marginTop: spacing.xs, color: colors.textHint, fontSize: 13, fontWeight: '500' },
  modalOverlay: { flex: 1, justifyContent: 'flex-end', backgroundColor: colors.modalScrim },
  groupSheet: {
    maxHeight: '88%',
    backgroundColor: colors.bgCard,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.lg,
    gap: spacing.sm,
    ...shadows.sheet,
  },
  sheetHandle: { alignSelf: 'center', width: 42, height: 5, borderRadius: 3, backgroundColor: colors.borderMedium },
  groupHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  groupTitle: { fontSize: 24, fontWeight: '600', color: colors.textPrimary },
  groupSubtitle: { fontSize: 13, fontWeight: '600', color: colors.textSecondary, marginTop: 2 },
  closeButton: { width: 36, height: 36, borderRadius: 18, backgroundColor: colors.bgSubtle, alignItems: 'center', justifyContent: 'center' },
  groupNameInput: {
    minHeight: 46,
    borderRadius: borderRadius.lg,
    borderWidth: 1,
    borderColor: colors.borderLight,
    backgroundColor: colors.white,
    paddingHorizontal: spacing.md,
    color: colors.textPrimary,
    fontSize: 15,
    fontWeight: '500',
  },
  searchInput: {
    minHeight: 46,
    borderRadius: borderRadius.lg,
    backgroundColor: colors.bgSubtle,
    paddingHorizontal: spacing.md,
    color: colors.textPrimary,
    fontSize: 15,
  },
  selectedRail: { gap: spacing.sm, paddingVertical: 2 },
  selectedChip: {
    minHeight: 34,
    borderRadius: 17,
    backgroundColor: colors.primary,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: spacing.md,
  },
  selectedChipText: { color: colors.textInverse, fontSize: 13, fontWeight: '600' },
  peopleLoading: { height: 180, alignItems: 'center', justifyContent: 'center' },
  peopleList: { maxHeight: 320 },
  personRow: {
    minHeight: 64,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  personAvatar: { width: 44, height: 44, borderRadius: 22 },
  personAvatarFallback: { width: 44, height: 44, borderRadius: 22, backgroundColor: colors.primaryLight, alignItems: 'center', justifyContent: 'center' },
  personAvatarText: { color: colors.primary, fontSize: 17, fontWeight: '500' },
  personInfo: { flex: 1 },
  personName: { color: colors.textPrimary, fontSize: 15, fontWeight: '600' },
  personHandle: { color: colors.textTertiary, fontSize: 12, fontWeight: '600', marginTop: 2 },
  pickCircle: { width: 26, height: 26, borderRadius: 13, borderWidth: 1.5, borderColor: colors.borderMedium, alignItems: 'center', justifyContent: 'center' },
  pickCircleOn: { backgroundColor: colors.primary, borderColor: colors.primary },
  noPeopleText: { textAlign: 'center', color: colors.textSecondary, fontSize: 14, fontWeight: '600', paddingVertical: spacing.xl },
  createGroupButton: { minHeight: 52, borderRadius: 26, backgroundColor: colors.primary, alignItems: 'center', justifyContent: 'center' },
  createGroupButtonDisabled: { opacity: 0.7 },
  createGroupText: { color: colors.textInverse, fontSize: 16, fontWeight: '500' },
});
