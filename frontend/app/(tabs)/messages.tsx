import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  RefreshControl,
  Modal,
  TextInput,
  Alert,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '../../src/utils/theme';
import api from '../../src/api/client';
import { formatDistanceToNow } from 'date-fns';
import { useAuthStore } from '../../src/store/authStore';
import { buildAgoraCallHref } from '../../src/utils/calls';
import { requireVerifiedPhone } from '../../src/utils/phoneVerification';

export default function MessagesScreen() {
  const router = useRouter();
  const user = useAuthStore((state) => state.user);
  const currentUserId = user?.id;
  const [conversations, setConversations] = useState<any[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [showGroupComposer, setShowGroupComposer] = useState(false);
  const [groupName, setGroupName] = useState('');
  const [peopleQuery, setPeopleQuery] = useState('');
  const [people, setPeople] = useState<any[]>([]);
  const [selectedPeople, setSelectedPeople] = useState<Record<string, any>>({});
  const [isPeopleLoading, setIsPeopleLoading] = useState(false);
  const [isCreatingGroup, setIsCreatingGroup] = useState(false);

  useEffect(() => {
    loadConversations();
  }, []);

  const loadConversations = async () => {
    try {
      const response = await api.get('/conversations');
      setConversations(response.data);
    } catch (error) {
      console.log('Error loading conversations:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const onRefresh = async () => {
    setIsRefreshing(true);
    await loadConversations();
    setIsRefreshing(false);
  };

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

  const renderConversation = ({ item }: { item: any }) => {
    if (item.type === 'group') {
      return (
        <TouchableOpacity
          style={styles.conversationItem}
          onPress={() => router.push(`/group-conversation/${item.group_id}` as any)}
        >
          <View style={styles.groupAvatar}>
            <Ionicons name="people" size={25} color={colors.textInverse} />
          </View>
          <View style={styles.conversationInfo}>
            <View style={styles.conversationHeader}>
              <Text style={styles.userName} numberOfLines={1}>{item.group_name || 'Group chat'}</Text>
              <Text style={styles.timeText}>
                {formatDistanceToNow(new Date(item.last_message_time || Date.now()), { addSuffix: false })}
              </Text>
            </View>
            <View style={styles.conversationPreview}>
              <Text style={styles.lastMessage} numberOfLines={1}>
                {item.last_message || `${item.member_count || 0} members`}
              </Text>
            </View>
          </View>
        </TouchableOpacity>
      );
    }

    const otherUser = item.other_user;
    const hasUnread = item.unread_count > 0;

    return (
      <TouchableOpacity
        style={styles.conversationItem}
        onPress={() => router.push(`/conversation/${otherUser.id}`)}
      >
        {otherUser.profile_image ? (
          <Image source={{ uri: otherUser.profile_image }} style={styles.avatar} />
        ) : (
          <View style={styles.avatarPlaceholder}>
            <Text style={styles.avatarText}>{otherUser.username[0].toUpperCase()}</Text>
          </View>
        )}
        <View style={styles.conversationInfo}>
          <View style={styles.conversationHeader}>
            <Text style={[styles.userName, hasUnread && styles.userNameUnread]}>
              {otherUser.full_name}
            </Text>
            <Text style={styles.timeText}>
              {formatDistanceToNow(new Date(item.last_message_time), { addSuffix: false })}
            </Text>
          </View>
          <View style={styles.conversationPreview}>
            <Text
              style={[styles.lastMessage, hasUnread && styles.lastMessageUnread]}
              numberOfLines={1}
            >
              {item.last_message}
            </Text>
            {hasUnread && (
              <View style={styles.unreadBadge}>
                <Text style={styles.unreadText}>{item.unread_count}</Text>
              </View>
            )}
          </View>
        </View>
        <TouchableOpacity
          style={styles.videoButton}
          onPress={() => startVideoCall(otherUser)}
          activeOpacity={0.75}
        >
          <Ionicons name="videocam-outline" size={23} color={colors.primary} />
        </TouchableOpacity>
      </TouchableOpacity>
    );
  };

  if (isLoading) {
    return (
      <SafeAreaView style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.primary} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.headerTitle}>Messages</Text>
        <TouchableOpacity style={styles.newMessageButton} onPress={openGroupComposer}>
          <Ionicons name="create-outline" size={24} color={colors.primary} />
        </TouchableOpacity>
      </View>

      {/* Conversations List */}
      <FlatList
        data={conversations}
        renderItem={renderConversation}
        keyExtractor={(item) => item.id}
        refreshControl={
          <RefreshControl
            refreshing={isRefreshing}
            onRefresh={onRefresh}
            tintColor={colors.primary}
          />
        }
        ListEmptyComponent={
          <View style={styles.emptyContainer}>
            <Ionicons name="chatbubbles-outline" size={64} color={colors.textTertiary} />
            <Text style={styles.emptyTitle}>No messages yet</Text>
            <Text style={styles.emptyText}>Start a conversation with someone!</Text>
          </View>
        }
        showsVerticalScrollIndicator={false}
      />

      <Modal visible={showGroupComposer} transparent animationType="slide" onRequestClose={() => setShowGroupComposer(false)}>
        <View style={styles.modalOverlay}>
          <View style={styles.groupSheet}>
            <View style={styles.sheetHandle} />
            <View style={styles.groupHeader}>
              <View>
                <Text style={styles.groupTitle}>New group</Text>
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
              <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={styles.selectedRail}>
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
                renderItem={({ item: person }) => {
                  const selected = !!selectedPeople[person.id];
                  return (
                    <TouchableOpacity style={styles.personRow} onPress={() => togglePerson(person)}>
                      {person.profile_image ? (
                        <Image source={{ uri: person.profile_image }} style={styles.personAvatar} />
                      ) : (
                        <View style={styles.personAvatarFallback}>
                          <Text style={styles.personAvatarText}>{String(person.full_name || person.username || 'F').slice(0, 1).toUpperCase()}</Text>
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
              {isCreatingGroup ? <ActivityIndicator color={colors.textInverse} /> : <Text style={styles.createGroupText}>Create group</Text>}
            </TouchableOpacity>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.sm,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  headerTitle: {
    fontSize: 28,
    fontWeight: '700',
    color: colors.textPrimary,
  },
  newMessageButton: {
    padding: spacing.xs,
  },
  conversationItem: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: spacing.md,
    paddingVertical: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderLight,
  },
  avatar: {
    width: 56,
    height: 56,
    borderRadius: 28,
  },
  avatarPlaceholder: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: colors.textInverse,
    fontSize: 22,
    fontWeight: '600',
  },
  groupAvatar: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: colors.primary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  conversationInfo: {
    flex: 1,
    marginLeft: spacing.md,
  },
  videoButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: spacing.sm,
  },
  conversationHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 4,
  },
  userName: {
    fontSize: 16,
    fontWeight: '500',
    color: colors.textPrimary,
  },
  userNameUnread: {
    fontWeight: '700',
  },
  timeText: {
    fontSize: 12,
    color: colors.textTertiary,
  },
  conversationPreview: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  lastMessage: {
    flex: 1,
    fontSize: 14,
    color: colors.textSecondary,
  },
  lastMessageUnread: {
    color: colors.textPrimary,
    fontWeight: '500',
  },
  unreadBadge: {
    backgroundColor: colors.primary,
    minWidth: 20,
    height: 20,
    borderRadius: 10,
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: spacing.sm,
    paddingHorizontal: 6,
  },
  unreadText: {
    color: colors.textInverse,
    fontSize: 11,
    fontWeight: '700',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 80,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: colors.textPrimary,
    marginTop: spacing.md,
  },
  emptyText: {
    fontSize: 14,
    color: colors.textSecondary,
    marginTop: spacing.xs,
  },
  modalOverlay: {
    flex: 1,
    justifyContent: 'flex-end',
    backgroundColor: 'rgba(0,0,0,0.35)',
  },
  groupSheet: {
    maxHeight: '88%',
    backgroundColor: colors.bgCard,
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    paddingHorizontal: spacing.md,
    paddingTop: spacing.sm,
    paddingBottom: spacing.lg,
    gap: spacing.sm,
  },
  sheetHandle: {
    alignSelf: 'center',
    width: 42,
    height: 5,
    borderRadius: 3,
    backgroundColor: colors.borderMedium,
  },
  groupHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  groupTitle: {
    fontSize: 24,
    fontWeight: '800',
    color: colors.textPrimary,
  },
  groupSubtitle: {
    fontSize: 13,
    fontWeight: '600',
    color: colors.textSecondary,
    marginTop: 2,
  },
  closeButton: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: colors.bgSubtle,
    alignItems: 'center',
    justifyContent: 'center',
  },
  groupNameInput: {
    minHeight: 46,
    borderRadius: borderRadius.lg,
    borderWidth: 1,
    borderColor: colors.borderLight,
    backgroundColor: colors.white,
    paddingHorizontal: spacing.md,
    color: colors.textPrimary,
    fontSize: 15,
    fontWeight: '700',
  },
  searchInput: {
    minHeight: 46,
    borderRadius: borderRadius.lg,
    backgroundColor: colors.bgSubtle,
    paddingHorizontal: spacing.md,
    color: colors.textPrimary,
    fontSize: 15,
  },
  selectedRail: {
    gap: spacing.sm,
    paddingVertical: 2,
  },
  selectedChip: {
    minHeight: 34,
    borderRadius: 17,
    backgroundColor: colors.primary,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: spacing.md,
  },
  selectedChipText: {
    color: colors.textInverse,
    fontSize: 13,
    fontWeight: '800',
  },
  peopleLoading: {
    height: 180,
    alignItems: 'center',
    justifyContent: 'center',
  },
  peopleList: {
    maxHeight: 320,
  },
  personRow: {
    minHeight: 64,
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.md,
    borderBottomWidth: 1,
    borderBottomColor: colors.borderSubtle,
  },
  personAvatar: {
    width: 44,
    height: 44,
    borderRadius: 22,
  },
  personAvatarFallback: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.primaryLight,
    alignItems: 'center',
    justifyContent: 'center',
  },
  personAvatarText: {
    color: colors.primary,
    fontSize: 17,
    fontWeight: '900',
  },
  personInfo: {
    flex: 1,
  },
  personName: {
    color: colors.textPrimary,
    fontSize: 15,
    fontWeight: '800',
  },
  personHandle: {
    color: colors.textTertiary,
    fontSize: 12,
    fontWeight: '600',
    marginTop: 2,
  },
  pickCircle: {
    width: 26,
    height: 26,
    borderRadius: 13,
    borderWidth: 1.5,
    borderColor: colors.borderMedium,
    alignItems: 'center',
    justifyContent: 'center',
  },
  pickCircleOn: {
    backgroundColor: colors.primary,
    borderColor: colors.primary,
  },
  noPeopleText: {
    textAlign: 'center',
    color: colors.textSecondary,
    fontSize: 14,
    fontWeight: '600',
    paddingVertical: spacing.xl,
  },
  createGroupButton: {
    minHeight: 52,
    borderRadius: 26,
    backgroundColor: colors.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  createGroupButtonDisabled: {
    opacity: 0.7,
  },
  createGroupText: {
    color: colors.textInverse,
    fontSize: 16,
    fontWeight: '900',
  },
});
