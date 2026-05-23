import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import api from '../../src/api/client';
import { useAuthStore } from '../../src/store/authStore';
import { colors, spacing } from '../../src/utils/theme';
import { isPhoneVerificationError, requireVerifiedPhone } from '../../src/utils/phoneVerification';

export default function GroupConversationScreen() {
  const router = useRouter();
  const { id: groupId } = useLocalSearchParams<{ id: string }>();
  const user = useAuthStore((state) => state.user);
  const [group, setGroup] = useState<any>(null);
  const [messages, setMessages] = useState<any[]>([]);
  const [newMessage, setNewMessage] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSending, setIsSending] = useState(false);
  const listRef = useRef<FlatList>(null);

  const loadData = useCallback(async () => {
    if (!groupId) return;
    try {
      const response = await api.get(`/group-chats/${groupId}/messages`);
      setGroup(response.data.group);
      setMessages(Array.isArray(response.data.messages) ? response.data.messages : []);
    } catch (error) {
      console.log('Group load failed:', error);
    } finally {
      setIsLoading(false);
    }
  }, [groupId]);

  useEffect(() => {
    loadData();
    const interval = setInterval(loadData, 5000);
    return () => clearInterval(interval);
  }, [loadData]);

  const sendMessage = async () => {
    const content = newMessage.trim();
    if (!content || isSending) return;
    if (!requireVerifiedPhone(user, router, 'send group messages')) return;

    setIsSending(true);
    setNewMessage('');
    try {
      await api.post(`/group-chats/${groupId}/messages`, { content });
      await loadData();
      listRef.current?.scrollToEnd({ animated: true });
    } catch (error: any) {
      if (isPhoneVerificationError(error)) {
        requireVerifiedPhone(null, router, 'send group messages');
      } else {
        Alert.alert('Message failed', error?.response?.data?.detail || 'Could not send this message.');
      }
    } finally {
      setIsSending(false);
    }
  };

  const renderMessage = ({ item }: { item: any }) => {
    const isOwn = item.sender_id === user?.id;
    return (
      <View style={[styles.messageRow, isOwn && styles.messageRowOwn]}>
        {!isOwn && (
          <Text style={styles.senderName} numberOfLines={1}>
            {item.full_name || item.username || 'Flames'}
          </Text>
        )}
        <View style={[styles.bubble, isOwn ? styles.bubbleOwn : styles.bubbleOther]}>
          <Text style={[styles.messageText, isOwn && styles.messageTextOwn]}>{item.content}</Text>
        </View>
      </View>
    );
  };

  if (isLoading) {
    return (
      <SafeAreaView style={styles.loading}>
        <ActivityIndicator size="large" color={colors.primary} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.header}>
        <TouchableOpacity style={styles.backButton} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={24} color="#000" />
        </TouchableOpacity>
        <View style={styles.groupIcon}>
          <Ionicons name="people" size={22} color={colors.textInverse} />
        </View>
        <View style={styles.headerText}>
          <Text style={styles.groupName} numberOfLines={1}>{group?.name || 'Group chat'}</Text>
          <Text style={styles.memberCount}>{Number(group?.member_count || 0)} members</Text>
        </View>
      </View>

      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={styles.body}>
        <FlatList
          ref={listRef}
          data={messages}
          renderItem={renderMessage}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.messageList}
          onContentSizeChange={() => listRef.current?.scrollToEnd({ animated: false })}
          ListEmptyComponent={
            <View style={styles.empty}>
              <Ionicons name="chatbubbles-outline" size={48} color={colors.textTertiary} />
              <Text style={styles.emptyText}>Start the group conversation.</Text>
            </View>
          }
        />

        <View style={styles.inputBar}>
          <TextInput
            style={styles.input}
            placeholder="Message the group..."
            placeholderTextColor={colors.textTertiary}
            value={newMessage}
            onChangeText={setNewMessage}
            multiline
            maxLength={1000}
          />
          <TouchableOpacity style={[styles.sendButton, !newMessage.trim() && styles.sendButtonDisabled]} onPress={sendMessage} disabled={!newMessage.trim() || isSending}>
            {isSending ? <ActivityIndicator size="small" color={colors.textInverse} /> : <Ionicons name="send" size={17} color={colors.textInverse} />}
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#F1F1F1' },
  loading: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: '#F1F1F1' },
  header: { minHeight: 64, flexDirection: 'row', alignItems: 'center', paddingHorizontal: spacing.sm, borderBottomWidth: 1, borderBottomColor: '#DEDEDE', backgroundColor: '#FFF' },
  backButton: { width: 44, height: 44, alignItems: 'center', justifyContent: 'center' },
  groupIcon: { width: 42, height: 42, borderRadius: 21, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center', marginRight: spacing.sm },
  headerText: { flex: 1, minWidth: 0 },
  groupName: { color: colors.textPrimary, fontSize: 17, fontWeight: '500' },
  memberCount: { color: colors.textTertiary, fontSize: 12, fontWeight: '500', marginTop: 2 },
  body: { flex: 1 },
  messageList: { flexGrow: 1, padding: spacing.md, gap: 10 },
  messageRow: { alignItems: 'flex-start' },
  messageRowOwn: { alignItems: 'flex-end' },
  senderName: { color: colors.textTertiary, fontSize: 11, fontWeight: '600', marginBottom: 3, marginLeft: 6, maxWidth: '80%' },
  bubble: { maxWidth: '74%', borderRadius: 22, paddingHorizontal: 18, paddingVertical: 12 },
  bubbleOwn: { backgroundColor: '#000' },
  bubbleOther: { backgroundColor: '#FFF' },
  messageText: { color: colors.textPrimary, fontSize: 15, lineHeight: 21 },
  messageTextOwn: { color: colors.textInverse },
  messageTime: { alignSelf: 'flex-end', color: colors.textTertiary, fontSize: 10, fontWeight: '500', marginTop: 4 },
  messageTimeOwn: { color: 'rgba(255,255,255,0.68)' },
  empty: { flex: 1, minHeight: 320, alignItems: 'center', justifyContent: 'center' },
  emptyText: { color: colors.textSecondary, fontSize: 14, fontWeight: '500', marginTop: spacing.sm },
  inputBar: { flexDirection: 'row', alignItems: 'flex-end', gap: spacing.sm, padding: spacing.md, borderTopWidth: 1, borderTopColor: '#DEDEDE', backgroundColor: '#FFF' },
  input: { flex: 1, maxHeight: 120, minHeight: 44, borderRadius: 22, backgroundColor: '#FFF', paddingHorizontal: spacing.md, paddingVertical: 11, color: '#111', fontSize: 15 },
  sendButton: { width: 44, height: 44, borderRadius: 22, backgroundColor: '#000', alignItems: 'center', justifyContent: 'center' },
  sendButtonDisabled: { opacity: 0.45 },
});
