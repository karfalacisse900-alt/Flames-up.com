import React, { useState, useEffect, useRef } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TextInput,
  TouchableOpacity,
  Image,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
  Alert,
  Modal,
  Pressable,
  Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, spacing, borderRadius } from '../../src/utils/theme';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { format } from 'date-fns';
import * as ImagePicker from 'expo-image-picker';

const { width: SCREEN_WIDTH } = Dimensions.get('window');

export default function ConversationScreen() {
  const router = useRouter();
  const { id: userId } = useLocalSearchParams<{ id: string }>();
  const { user } = useAuthStore();
  const [messages, setMessages] = useState<any[]>([]);
  const [otherUser, setOtherUser] = useState<any>(null);
  const [newMessage, setNewMessage] = useState('');
  const [isLoading, setIsLoading] = useState(true);
  const [isSending, setIsSending] = useState(false);
  const [selectedMedia, setSelectedMedia] = useState<{ uri: string; type: 'image' | 'video'; base64?: string } | null>(null);
  const [showAttachMenu, setShowAttachMenu] = useState(false);
  const [viewingMedia, setViewingMedia] = useState<string | null>(null);
  const flatListRef = useRef<FlatList>(null);

  useEffect(() => {
    loadData();
    const interval = setInterval(loadMessages, 5000);
    return () => clearInterval(interval);
  }, [userId]);

  const loadData = async () => {
    try {
      const [messagesRes, userRes] = await Promise.all([
        api.get(`/messages/${userId}`),
        api.get(`/users/${userId}`),
      ]);
      setMessages(messagesRes.data);
      setOtherUser(userRes.data);
    } catch (error) {
      console.log('Error loading conversation:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const loadMessages = async () => {
    try {
      const response = await api.get(`/messages/${userId}`);
      setMessages(response.data);
    } catch (error) {
      console.log('Error loading messages:', error);
    }
  };

  const pickImage = async () => {
    setShowAttachMenu(false);
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Please allow access to your photo library.');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: true,
      quality: 0.7,
      base64: true,
    });
    if (!result.canceled && result.assets[0]) {
      const asset = result.assets[0];
      setSelectedMedia({
        uri: asset.uri,
        type: 'image',
        base64: asset.base64 || undefined,
      });
    }
  };

  const pickVideo = async () => {
    setShowAttachMenu(false);
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Please allow access to your photo library.');
      return;
    }
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['videos'],
      allowsEditing: true,
      quality: 0.5,
      videoMaxDuration: 60,
      base64: true,
    });
    if (!result.canceled && result.assets[0]) {
      const asset = result.assets[0];
      setSelectedMedia({
        uri: asset.uri,
        type: 'video',
        base64: asset.base64 || undefined,
      });
    }
  };

  const takePhoto = async () => {
    setShowAttachMenu(false);
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') {
      Alert.alert('Permission needed', 'Please allow camera access.');
      return;
    }
    const result = await ImagePicker.launchCameraAsync({
      allowsEditing: true,
      quality: 0.7,
      base64: true,
    });
    if (!result.canceled && result.assets[0]) {
      const asset = result.assets[0];
      setSelectedMedia({
        uri: asset.uri,
        type: 'image',
        base64: asset.base64 || undefined,
      });
    }
  };

  const clearMedia = () => {
    setSelectedMedia(null);
  };

  const sendMessage = async () => {
    if ((!newMessage.trim() && !selectedMedia) || isSending) return;

    setIsSending(true);
    const messageText = newMessage.trim();
    setNewMessage('');
    const media = selectedMedia;
    setSelectedMedia(null);

    try {
      const payload: any = {
        receiver_id: userId,
        content: messageText,
      };

      if (media) {
        if (media.base64) {
          payload.media_url = `data:${media.type === 'video' ? 'video/mp4' : 'image/jpeg'};base64,${media.base64}`;
        } else {
          payload.media_url = media.uri;
        }
        payload.media_type = media.type;
      }

      await api.post('/messages', payload);
      await loadMessages();
      flatListRef.current?.scrollToEnd({ animated: true });
    } catch (error) {
      console.log('Error sending message:', error);
      setNewMessage(messageText);
      if (media) setSelectedMedia(media);
      Alert.alert('Error', 'Failed to send message. Try again.');
    } finally {
      setIsSending(false);
    }
  };

  const renderMessage = ({ item }: { item: any }) => {
    const isOwn = item.sender_id === user?.id;
    const hasMedia = item.media_url || item.image;
    const mediaType = item.media_type || (item.image ? 'image' : null);
    const mediaSource = item.media_url || item.image;

    return (
      <View style={[styles.messageContainer, isOwn && styles.messageContainerOwn]}>
        <View style={[
          styles.messageBubble,
          isOwn ? styles.messageBubbleOwn : styles.messageBubbleOther,
          hasMedia && styles.mediaBubble,
        ]}>
          {/* Media content */}
          {hasMedia && mediaType === 'image' && (
            <TouchableOpacity onPress={() => setViewingMedia(mediaSource)} activeOpacity={0.9}>
              <Image
                source={{ uri: mediaSource }}
                style={styles.messageImage}
                resizeMode="cover"
              />
            </TouchableOpacity>
          )}
          {hasMedia && mediaType === 'video' && (
            <TouchableOpacity style={styles.videoContainer} onPress={() => setViewingMedia(mediaSource)}>
              <View style={styles.videoOverlay}>
                <View style={styles.playButton}>
                  <Ionicons name="play" size={28} color="#FFF" />
                </View>
                <Text style={styles.videoLabel}>Video</Text>
              </View>
            </TouchableOpacity>
          )}
          {/* Text content */}
          {item.content ? (
            <Text style={[styles.messageText, isOwn && styles.messageTextOwn]}>
              {item.content}
            </Text>
          ) : null}
          <Text style={[styles.messageTime, isOwn && styles.messageTimeOwn]}>
            {format(new Date(item.created_at), 'HH:mm')}
          </Text>
        </View>
      </View>
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
        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
          <Ionicons name="arrow-back" size={24} color={colors.textPrimary} />
        </TouchableOpacity>
        <TouchableOpacity
          style={styles.headerUser}
          onPress={() => router.push(`/user/${userId}`)}
        >
          {otherUser?.profile_image ? (
            <Image source={{ uri: otherUser.profile_image }} style={styles.headerAvatar} />
          ) : (
            <View style={styles.headerAvatarPlaceholder}>
              <Text style={styles.headerAvatarText}>
                {otherUser?.username?.[0]?.toUpperCase() || '?'}
              </Text>
            </View>
          )}
          <View>
            <Text style={styles.headerName}>{otherUser?.full_name}</Text>
            <Text style={styles.headerHandle}>@{otherUser?.username}</Text>
          </View>
        </TouchableOpacity>
      </View>

      <KeyboardAvoidingView
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
        style={styles.keyboardView}
        keyboardVerticalOffset={Platform.OS === 'ios' ? 0 : 20}
      >
        {/* Messages */}
        <FlatList
          ref={flatListRef}
          data={messages}
          renderItem={renderMessage}
          keyExtractor={(item) => item.id}
          contentContainerStyle={styles.messagesList}
          onContentSizeChange={() => flatListRef.current?.scrollToEnd({ animated: false })}
          ListEmptyComponent={
            <View style={styles.emptyContainer}>
              <Ionicons name="chatbubble-outline" size={48} color={colors.textTertiary} />
              <Text style={styles.emptyText}>No messages yet. Say hi!</Text>
            </View>
          }
        />

        {/* Media Preview */}
        {selectedMedia && (
          <View style={styles.mediaPreview}>
            {selectedMedia.type === 'image' ? (
              <Image source={{ uri: selectedMedia.uri }} style={styles.previewImage} />
            ) : (
              <View style={styles.previewVideo}>
                <Ionicons name="videocam" size={24} color="#FFF" />
                <Text style={styles.previewVideoText}>Video selected</Text>
              </View>
            )}
            <TouchableOpacity style={styles.removeMedia} onPress={clearMedia}>
              <Ionicons name="close-circle" size={24} color="#EF4444" />
            </TouchableOpacity>
          </View>
        )}

        {/* Input Area */}
        <View style={styles.inputContainer}>
          <TouchableOpacity
            style={styles.attachBtn}
            onPress={() => setShowAttachMenu(true)}
          >
            <Ionicons name="add-circle" size={28} color={colors.primary || '#2D6A4F'} />
          </TouchableOpacity>
          <TextInput
            style={styles.input}
            placeholder="Type a message..."
            placeholderTextColor={colors.textTertiary}
            value={newMessage}
            onChangeText={setNewMessage}
            multiline
            maxLength={1000}
          />
          <TouchableOpacity
            style={[
              styles.sendButton,
              (!newMessage.trim() && !selectedMedia || isSending) && styles.sendButtonDisabled,
            ]}
            onPress={sendMessage}
            disabled={(!newMessage.trim() && !selectedMedia) || isSending}
          >
            {isSending ? (
              <ActivityIndicator size="small" color="#FFF" />
            ) : (
              <Ionicons name="send" size={18} color="#FFF" />
            )}
          </TouchableOpacity>
        </View>
      </KeyboardAvoidingView>

      {/* Attach Menu Modal */}
      <Modal visible={showAttachMenu} transparent animationType="fade" onRequestClose={() => setShowAttachMenu(false)}>
        <Pressable style={styles.attachOverlay} onPress={() => setShowAttachMenu(false)}>
          <View style={styles.attachSheet}>
            <View style={styles.attachHandle} />
            <Text style={styles.attachTitle}>Share Media</Text>
            <View style={styles.attachOptions}>
              <TouchableOpacity style={styles.attachOption} onPress={pickImage}>
                <View style={[styles.attachIconBox, { backgroundColor: '#DCFCE7' }]}>
                  <Ionicons name="image" size={26} color="#16A34A" />
                </View>
                <Text style={styles.attachLabel}>Photo</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.attachOption} onPress={pickVideo}>
                <View style={[styles.attachIconBox, { backgroundColor: '#DBEAFE' }]}>
                  <Ionicons name="videocam" size={26} color="#2563EB" />
                </View>
                <Text style={styles.attachLabel}>Video</Text>
              </TouchableOpacity>
              <TouchableOpacity style={styles.attachOption} onPress={takePhoto}>
                <View style={[styles.attachIconBox, { backgroundColor: '#FEF3C7' }]}>
                  <Ionicons name="camera" size={26} color="#D97706" />
                </View>
                <Text style={styles.attachLabel}>Camera</Text>
              </TouchableOpacity>
            </View>
          </View>
        </Pressable>
      </Modal>

      {/* Full Image Viewer */}
      <Modal visible={!!viewingMedia} transparent animationType="fade" onRequestClose={() => setViewingMedia(null)}>
        <Pressable style={styles.imageViewerOverlay} onPress={() => setViewingMedia(null)}>
          <TouchableOpacity style={styles.closeViewer} onPress={() => setViewingMedia(null)}>
            <Ionicons name="close" size={28} color="#FFF" />
          </TouchableOpacity>
          {viewingMedia && (
            <Image
              source={{ uri: viewingMedia }}
              style={styles.fullImage}
              resizeMode="contain"
            />
          )}
        </Pressable>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#FAFAF8',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#FAFAF8',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
    borderBottomWidth: 1,
    borderBottomColor: '#F0ECE5',
    backgroundColor: '#FFF',
  },
  backButton: {
    width: 44,
    height: 44,
    justifyContent: 'center',
    alignItems: 'center',
  },
  headerUser: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    marginLeft: 4,
  },
  headerAvatar: {
    width: 40,
    height: 40,
    borderRadius: 20,
    marginRight: 10,
  },
  headerAvatarPlaceholder: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#2D6A4F',
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: 10,
  },
  headerAvatarText: {
    color: '#FFF',
    fontSize: 16,
    fontWeight: '700',
  },
  headerName: {
    fontSize: 16,
    fontWeight: '700',
    color: '#1B4332',
  },
  headerHandle: {
    fontSize: 12,
    color: '#9CA3AF',
  },
  keyboardView: {
    flex: 1,
  },
  messagesList: {
    padding: 16,
    flexGrow: 1,
  },
  messageContainer: {
    marginBottom: 8,
    alignItems: 'flex-start',
  },
  messageContainerOwn: {
    alignItems: 'flex-end',
  },
  messageBubble: {
    maxWidth: '80%',
    padding: 10,
    borderRadius: 18,
  },
  mediaBubble: {
    padding: 4,
    overflow: 'hidden',
  },
  messageBubbleOwn: {
    backgroundColor: '#2D6A4F',
    borderBottomRightRadius: 4,
  },
  messageBubbleOther: {
    backgroundColor: '#F3F0EB',
    borderBottomLeftRadius: 4,
  },
  messageImage: {
    width: SCREEN_WIDTH * 0.6,
    height: SCREEN_WIDTH * 0.45,
    borderRadius: 14,
  },
  videoContainer: {
    width: SCREEN_WIDTH * 0.6,
    height: SCREEN_WIDTH * 0.35,
    borderRadius: 14,
    backgroundColor: '#1B4332',
    justifyContent: 'center',
    alignItems: 'center',
  },
  videoOverlay: {
    alignItems: 'center',
    gap: 6,
  },
  playButton: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: 'rgba(255,255,255,0.2)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  videoLabel: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.7)',
    fontWeight: '500',
  },
  messageText: {
    fontSize: 15,
    color: '#1B4332',
    lineHeight: 20,
    paddingHorizontal: 6,
    paddingTop: 4,
  },
  messageTextOwn: {
    color: '#FFF',
  },
  messageTime: {
    fontSize: 10,
    color: '#9CA3AF',
    marginTop: 3,
    alignSelf: 'flex-end',
    paddingHorizontal: 6,
    paddingBottom: 2,
  },
  messageTimeOwn: {
    color: 'rgba(255,255,255,0.6)',
  },
  emptyContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 60,
    gap: 8,
  },
  emptyText: {
    fontSize: 14,
    color: '#9CA3AF',
  },
  // Media preview above input
  mediaPreview: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingVertical: 8,
    backgroundColor: '#FFF',
    borderTopWidth: 1,
    borderTopColor: '#F0ECE5',
  },
  previewImage: {
    width: 60,
    height: 60,
    borderRadius: 10,
  },
  previewVideo: {
    width: 60,
    height: 60,
    borderRadius: 10,
    backgroundColor: '#1B4332',
    justifyContent: 'center',
    alignItems: 'center',
  },
  previewVideoText: {
    fontSize: 8,
    color: '#FFF',
    marginTop: 2,
  },
  removeMedia: {
    marginLeft: 8,
    padding: 4,
  },
  // Input area
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    paddingHorizontal: 10,
    paddingVertical: 8,
    borderTopWidth: 1,
    borderTopColor: '#F0ECE5',
    backgroundColor: '#FFF',
    gap: 6,
  },
  attachBtn: {
    width: 44,
    height: 44,
    justifyContent: 'center',
    alignItems: 'center',
  },
  input: {
    flex: 1,
    backgroundColor: '#F3F0EB',
    borderRadius: 20,
    paddingHorizontal: 16,
    paddingVertical: 10,
    fontSize: 15,
    color: '#1B4332',
    maxHeight: 100,
  },
  sendButton: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: '#2D6A4F',
    justifyContent: 'center',
    alignItems: 'center',
  },
  sendButtonDisabled: {
    opacity: 0.4,
  },
  // Attach menu
  attachOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.3)',
    justifyContent: 'flex-end',
  },
  attachSheet: {
    backgroundColor: '#FFF',
    borderTopLeftRadius: 24,
    borderTopRightRadius: 24,
    paddingHorizontal: 24,
    paddingBottom: 40,
    paddingTop: 12,
  },
  attachHandle: {
    width: 40,
    height: 4,
    backgroundColor: '#D1D5DB',
    borderRadius: 2,
    alignSelf: 'center',
    marginBottom: 16,
  },
  attachTitle: {
    fontSize: 18,
    fontWeight: '700',
    color: '#1B4332',
    marginBottom: 20,
    textAlign: 'center',
  },
  attachOptions: {
    flexDirection: 'row',
    justifyContent: 'space-around',
  },
  attachOption: {
    alignItems: 'center',
    gap: 8,
  },
  attachIconBox: {
    width: 60,
    height: 60,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
  },
  attachLabel: {
    fontSize: 13,
    fontWeight: '600',
    color: '#374151',
  },
  // Full image viewer
  imageViewerOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.95)',
    justifyContent: 'center',
    alignItems: 'center',
  },
  closeViewer: {
    position: 'absolute',
    top: 50,
    right: 20,
    zIndex: 10,
    width: 44,
    height: 44,
    justifyContent: 'center',
    alignItems: 'center',
  },
  fullImage: {
    width: SCREEN_WIDTH,
    height: SCREEN_WIDTH,
  },
});
