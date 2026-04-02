import React, { useState, useEffect, useRef } from 'react';
import {
  View, Text, StyleSheet, FlatList, TextInput, TouchableOpacity,
  Image, KeyboardAvoidingView, Platform, ActivityIndicator, Alert,
  Modal, Pressable, Dimensions, Animated,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useAuthStore } from '../../src/store/authStore';
import api from '../../src/api/client';
import { format } from 'date-fns';
import * as ImagePicker from 'expo-image-picker';
import { Audio } from 'expo-av';

const { width: SW } = Dimensions.get('window');

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
  const [isTyping, setIsTyping] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [recording, setRecording] = useState<Audio.Recording | null>(null);
  const [recordDuration, setRecordDuration] = useState(0);
  const [playingVoice, setPlayingVoice] = useState<string | null>(null);
  const flatListRef = useRef<FlatList>(null);
  const typingTimeout = useRef<any>(null);
  const recordTimer = useRef<any>(null);
  const pulseAnim = useRef(new Animated.Value(1)).current;

  useEffect(() => {
    loadData();
    const interval = setInterval(loadMessages, 4000);
    return () => { clearInterval(interval); if (typingTimeout.current) clearTimeout(typingTimeout.current); };
  }, [userId]);

  useEffect(() => {
    if (isRecording) {
      Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, { toValue: 1.3, duration: 600, useNativeDriver: true }),
          Animated.timing(pulseAnim, { toValue: 1, duration: 600, useNativeDriver: true }),
        ])
      ).start();
    } else {
      pulseAnim.setValue(1);
    }
  }, [isRecording]);

  const loadData = async () => {
    try {
      const [messagesRes, userRes] = await Promise.all([
        api.get(`/messages/${userId}`),
        api.get(`/users/${userId}`),
      ]);
      setMessages(messagesRes.data);
      setOtherUser(userRes.data);
    } catch (e) { console.log('Load error:', e); }
    finally { setIsLoading(false); }
  };

  const loadMessages = async () => {
    try {
      const r = await api.get(`/messages/${userId}`);
      setMessages(r.data);
    } catch {}
  };

  const handleTextChange = (text: string) => {
    setNewMessage(text);
    // Typing indicator logic
    if (typingTimeout.current) clearTimeout(typingTimeout.current);
    if (text.length > 0) {
      setIsTyping(true);
      typingTimeout.current = setTimeout(() => setIsTyping(false), 2000);
    } else {
      setIsTyping(false);
    }
  };

  const pickImage = async () => {
    setShowAttachMenu(false);
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') { Alert.alert('Permission needed'); return; }
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'], allowsEditing: true, quality: 0.7, base64: true,
    });
    if (!result.canceled && result.assets[0]) {
      setSelectedMedia({ uri: result.assets[0].uri, type: 'image', base64: result.assets[0].base64 || undefined });
    }
  };

  const pickVideo = async () => {
    setShowAttachMenu(false);
    const { status } = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (status !== 'granted') { Alert.alert('Permission needed'); return; }
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['videos'], allowsEditing: true, quality: 0.5, videoMaxDuration: 60,
    });
    if (!result.canceled && result.assets[0]) {
      setSelectedMedia({ uri: result.assets[0].uri, type: 'video' });
    }
  };

  const takePhoto = async () => {
    setShowAttachMenu(false);
    const { status } = await ImagePicker.requestCameraPermissionsAsync();
    if (status !== 'granted') { Alert.alert('Permission needed'); return; }
    const result = await ImagePicker.launchCameraAsync({ allowsEditing: true, quality: 0.7, base64: true });
    if (!result.canceled && result.assets[0]) {
      setSelectedMedia({ uri: result.assets[0].uri, type: 'image', base64: result.assets[0].base64 || undefined });
    }
  };

  // Voice recording
  const startRecording = async () => {
    try {
      const perm = await Audio.requestPermissionsAsync();
      if (!perm.granted) { Alert.alert('Permission needed', 'Microphone access required'); return; }
      await Audio.setAudioModeAsync({ allowsRecordingIOS: true, playsInSilentModeIOS: true });
      const { recording: rec } = await Audio.Recording.createAsync(Audio.RecordingOptionsPresets.HIGH_QUALITY);
      setRecording(rec);
      setIsRecording(true);
      setRecordDuration(0);
      recordTimer.current = setInterval(() => setRecordDuration(d => d + 1), 1000);
    } catch (e) { console.log('Record error:', e); Alert.alert('Error', 'Could not start recording'); }
  };

  const stopRecording = async () => {
    if (!recording) return;
    clearInterval(recordTimer.current);
    setIsRecording(false);
    try {
      await recording.stopAndUnloadAsync();
      const uri = recording.getURI();
      setRecording(null);
      if (uri && recordDuration >= 1) {
        // Send as voice message
        sendMessage(undefined, uri, 'voice');
      }
    } catch (e) { console.log('Stop error:', e); }
  };

  const cancelRecording = async () => {
    if (!recording) return;
    clearInterval(recordTimer.current);
    setIsRecording(false);
    try {
      await recording.stopAndUnloadAsync();
      setRecording(null);
    } catch {}
  };

  const playVoiceMessage = async (uri: string) => {
    try {
      if (playingVoice === uri) {
        setPlayingVoice(null);
        return;
      }
      await Audio.setAudioModeAsync({ allowsRecordingIOS: false, playsInSilentModeIOS: true });
      const { sound } = await Audio.Sound.createAsync({ uri });
      setPlayingVoice(uri);
      sound.setOnPlaybackStatusUpdate((status: any) => {
        if (status.didJustFinish) setPlayingVoice(null);
      });
      await sound.playAsync();
    } catch (e) { console.log('Play error:', e); }
  };

  const sendMessage = async (text?: string, mediaUri?: string, mediaType?: string) => {
    const msgText = text ?? newMessage.trim();
    const media = mediaUri ? { uri: mediaUri, type: (mediaType || 'image') as 'image' | 'video' } : selectedMedia;

    if (!msgText && !media) return;
    if (isSending) return;

    setIsSending(true);
    setNewMessage('');
    setSelectedMedia(null);

    try {
      const payload: any = { receiver_id: userId, content: msgText || '' };
      if (media) {
        if (media.type === 'image' && (media as any).base64) {
          // Upload image to CF Images
          try {
            const imgData = `data:image/jpeg;base64,${(media as any).base64}`;
            const res = await api.post('/upload/image', { image: imgData });
            payload.media_url = res.data?.url || imgData;
          } catch { payload.media_url = media.uri; }
        } else {
          payload.media_url = media.uri;
        }
        payload.media_type = mediaType || media.type;
      }
      await api.post('/messages', payload);
      await loadMessages();
      flatListRef.current?.scrollToEnd({ animated: true });
    } catch (e) {
      Alert.alert('Error', 'Failed to send message');
    } finally { setIsSending(false); }
  };

  const formatDuration = (sec: number) => `${Math.floor(sec / 60)}:${String(sec % 60).padStart(2, '0')}`;

  const renderMessage = ({ item }: { item: any }) => {
    const isOwn = item.sender_id === user?.id;
    const hasMedia = item.media_url || item.image;
    const mediaType = item.media_type || (item.image ? 'image' : null);
    const mediaSource = item.media_url || item.image;
    const isVoice = mediaType === 'voice';

    return (
      <View style={[st.msgRow, isOwn && st.msgRowOwn]}>
        <View style={[st.bubble, isOwn ? st.bubbleOwn : st.bubbleOther, hasMedia && !isVoice && st.mediaBubble]}>
          {/* Image */}
          {hasMedia && mediaType === 'image' && (
            <TouchableOpacity onPress={() => setViewingMedia(mediaSource)} activeOpacity={0.9}>
              <Image source={{ uri: mediaSource }} style={st.msgImage} resizeMode="cover" />
            </TouchableOpacity>
          )}
          {/* Video */}
          {hasMedia && mediaType === 'video' && (
            <TouchableOpacity style={st.videoBox} onPress={() => setViewingMedia(mediaSource)}>
              <View style={st.playCircle}><Ionicons name="play" size={28} color="#FFF" /></View>
              <Text style={st.videoLabel}>Video</Text>
            </TouchableOpacity>
          )}
          {/* Voice message */}
          {isVoice && (
            <TouchableOpacity style={st.voiceBubble} onPress={() => playVoiceMessage(mediaSource)}>
              <Ionicons name={playingVoice === mediaSource ? 'pause' : 'play'} size={20} color={isOwn ? '#FFF' : '#2D6A4F'} />
              <View style={st.voiceWave}>
                {[...Array(12)].map((_, i) => (
                  <View key={i} style={[st.waveBar, { height: 6 + Math.random() * 14, backgroundColor: isOwn ? 'rgba(255,255,255,0.5)' : 'rgba(45,106,79,0.4)' }]} />
                ))}
              </View>
              <Ionicons name="mic" size={14} color={isOwn ? 'rgba(255,255,255,0.5)' : '#9CA3AF'} />
            </TouchableOpacity>
          )}
          {/* Text */}
          {item.content ? <Text style={[st.msgText, isOwn && st.msgTextOwn]}>{item.content}</Text> : null}
          {/* Time + read receipt */}
          <View style={st.metaRow}>
            <Text style={[st.msgTime, isOwn && st.msgTimeOwn]}>
              {format(new Date(item.created_at), 'HH:mm')}
            </Text>
            {isOwn && (
              <Ionicons
                name={item.is_read ? 'checkmark-done' : 'checkmark'}
                size={14}
                color={item.is_read ? '#60A5FA' : (isOwn ? 'rgba(255,255,255,0.4)' : '#9CA3AF')}
                style={{ marginLeft: 3 }}
              />
            )}
          </View>
        </View>
      </View>
    );
  };

  if (isLoading) return <SafeAreaView style={st.loading}><ActivityIndicator size="large" color="#2D6A4F" /></SafeAreaView>;

  return (
    <SafeAreaView style={st.container} edges={['top']}>
      {/* Header */}
      <View style={st.header}>
        <TouchableOpacity onPress={() => router.back()} style={st.backBtn}>
          <Ionicons name="arrow-back" size={24} color="#1B4332" />
        </TouchableOpacity>
        <TouchableOpacity style={st.headerUser} onPress={() => router.push(`/user/${userId}`)}>
          {otherUser?.profile_image ? (
            <Image source={{ uri: otherUser.profile_image }} style={st.avatar} />
          ) : (
            <View style={st.avatarFallback}><Text style={st.avatarText}>{otherUser?.username?.[0]?.toUpperCase() || '?'}</Text></View>
          )}
          <View>
            <Text style={st.headerName}>{otherUser?.full_name}</Text>
            <Text style={st.headerHandle}>@{otherUser?.username}</Text>
          </View>
        </TouchableOpacity>
      </View>

      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : 'height'} style={{ flex: 1 }} keyboardVerticalOffset={0}>
        <FlatList
          ref={flatListRef}
          data={messages}
          renderItem={renderMessage}
          keyExtractor={(item) => item.id}
          contentContainerStyle={st.msgList}
          onContentSizeChange={() => flatListRef.current?.scrollToEnd({ animated: false })}
          ListEmptyComponent={
            <View style={st.empty}><Ionicons name="chatbubble-outline" size={48} color="#D1D5DB" /><Text style={st.emptyText}>No messages yet. Say hi!</Text></View>
          }
        />

        {/* Media preview */}
        {selectedMedia && (
          <View style={st.mediaPreview}>
            {selectedMedia.type === 'image' ? (
              <Image source={{ uri: selectedMedia.uri }} style={st.previewImg} />
            ) : (
              <View style={st.previewVid}><Ionicons name="videocam" size={22} color="#FFF" /><Text style={st.previewVidText}>Video</Text></View>
            )}
            <TouchableOpacity style={st.removeMedia} onPress={() => setSelectedMedia(null)}>
              <Ionicons name="close-circle" size={22} color="#EF4444" />
            </TouchableOpacity>
          </View>
        )}

        {/* Voice recording indicator */}
        {isRecording && (
          <View style={st.recordingBar}>
            <TouchableOpacity onPress={cancelRecording} style={st.cancelRecBtn}>
              <Ionicons name="trash" size={18} color="#EF4444" />
            </TouchableOpacity>
            <Animated.View style={[st.recDot, { transform: [{ scale: pulseAnim }] }]} />
            <Text style={st.recTime}>{formatDuration(recordDuration)}</Text>
            <Text style={st.recLabel}>Recording...</Text>
            <TouchableOpacity onPress={stopRecording} style={st.sendRecBtn}>
              <Ionicons name="send" size={16} color="#FFF" />
            </TouchableOpacity>
          </View>
        )}

        {/* Input area */}
        {!isRecording && (
          <View style={st.inputBar}>
            <TouchableOpacity style={st.attachBtn} onPress={() => setShowAttachMenu(true)}>
              <Ionicons name="add-circle" size={28} color="#2D6A4F" />
            </TouchableOpacity>
            <TextInput
              style={st.input}
              placeholder="Type a message..."
              placeholderTextColor="#9CA3AF"
              value={newMessage}
              onChangeText={handleTextChange}
              multiline
              maxLength={1000}
            />
            {newMessage.trim() || selectedMedia ? (
              <TouchableOpacity style={st.sendBtn} onPress={() => sendMessage()} disabled={isSending}>
                {isSending ? <ActivityIndicator size="small" color="#FFF" /> : <Ionicons name="send" size={16} color="#FFF" />}
              </TouchableOpacity>
            ) : (
              <TouchableOpacity style={st.micBtn} onPress={startRecording}>
                <Ionicons name="mic" size={22} color="#2D6A4F" />
              </TouchableOpacity>
            )}
          </View>
        )}
      </KeyboardAvoidingView>

      {/* Attach menu */}
      <Modal visible={showAttachMenu} transparent animationType="fade" onRequestClose={() => setShowAttachMenu(false)}>
        <Pressable style={st.attachOverlay} onPress={() => setShowAttachMenu(false)}>
          <View style={st.attachSheet}>
            <View style={st.attachHandle} />
            <Text style={st.attachTitle}>Share Media</Text>
            <View style={st.attachOpts}>
              <TouchableOpacity style={st.attachOpt} onPress={pickImage}>
                <View style={[st.attachIconBox, { backgroundColor: '#DCFCE7' }]}><Ionicons name="image" size={26} color="#16A34A" /></View>
                <Text style={st.attachLabel}>Photo</Text>
              </TouchableOpacity>
              <TouchableOpacity style={st.attachOpt} onPress={pickVideo}>
                <View style={[st.attachIconBox, { backgroundColor: '#DBEAFE' }]}><Ionicons name="videocam" size={26} color="#2563EB" /></View>
                <Text style={st.attachLabel}>Video</Text>
              </TouchableOpacity>
              <TouchableOpacity style={st.attachOpt} onPress={takePhoto}>
                <View style={[st.attachIconBox, { backgroundColor: '#FEF3C7' }]}><Ionicons name="camera" size={26} color="#D97706" /></View>
                <Text style={st.attachLabel}>Camera</Text>
              </TouchableOpacity>
            </View>
          </View>
        </Pressable>
      </Modal>

      {/* Image viewer */}
      <Modal visible={!!viewingMedia} transparent animationType="fade" onRequestClose={() => setViewingMedia(null)}>
        <Pressable style={st.viewerOverlay} onPress={() => setViewingMedia(null)}>
          <TouchableOpacity style={st.closeViewer} onPress={() => setViewingMedia(null)}><Ionicons name="close" size={28} color="#FFF" /></TouchableOpacity>
          {viewingMedia && <Image source={{ uri: viewingMedia }} style={st.fullImg} resizeMode="contain" />}
        </Pressable>
      </Modal>
    </SafeAreaView>
  );
}

const st = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },
  loading: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#FAFAF8' },
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 12, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: '#F0ECE5', backgroundColor: '#FFF' },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerUser: { flexDirection: 'row', alignItems: 'center', flex: 1, marginLeft: 4 },
  avatar: { width: 40, height: 40, borderRadius: 20, marginRight: 10 },
  avatarFallback: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#2D6A4F', justifyContent: 'center', alignItems: 'center', marginRight: 10 },
  avatarText: { color: '#FFF', fontSize: 16, fontWeight: '700' },
  headerName: { fontSize: 16, fontWeight: '700', color: '#1B4332' },
  headerHandle: { fontSize: 12, color: '#9CA3AF' },
  msgList: { padding: 16, flexGrow: 1 },
  msgRow: { marginBottom: 6, alignItems: 'flex-start' },
  msgRowOwn: { alignItems: 'flex-end' },
  bubble: { maxWidth: '80%', padding: 10, borderRadius: 18 },
  mediaBubble: { padding: 4, overflow: 'hidden' },
  bubbleOwn: { backgroundColor: '#2D6A4F', borderBottomRightRadius: 4 },
  bubbleOther: { backgroundColor: '#F3F0EB', borderBottomLeftRadius: 4 },
  msgImage: { width: SW * 0.6, height: SW * 0.45, borderRadius: 14 },
  videoBox: { width: SW * 0.6, height: SW * 0.35, borderRadius: 14, backgroundColor: '#1B4332', justifyContent: 'center', alignItems: 'center' },
  playCircle: { width: 52, height: 52, borderRadius: 26, backgroundColor: 'rgba(255,255,255,0.2)', justifyContent: 'center', alignItems: 'center' },
  videoLabel: { fontSize: 12, color: 'rgba(255,255,255,0.7)', fontWeight: '500', marginTop: 4 },
  voiceBubble: { flexDirection: 'row', alignItems: 'center', gap: 8, paddingHorizontal: 6, paddingVertical: 4, minWidth: 160 },
  voiceWave: { flexDirection: 'row', alignItems: 'center', gap: 2, flex: 1 },
  waveBar: { width: 3, borderRadius: 1.5 },
  msgText: { fontSize: 15, color: '#1B4332', lineHeight: 20, paddingHorizontal: 6, paddingTop: 4 },
  msgTextOwn: { color: '#FFF' },
  metaRow: { flexDirection: 'row', alignItems: 'center', alignSelf: 'flex-end', paddingHorizontal: 6, paddingBottom: 2, marginTop: 2 },
  msgTime: { fontSize: 10, color: '#9CA3AF' },
  msgTimeOwn: { color: 'rgba(255,255,255,0.5)' },
  empty: { flex: 1, justifyContent: 'center', alignItems: 'center', paddingVertical: 60, gap: 8 },
  emptyText: { fontSize: 14, color: '#9CA3AF' },
  // Media preview
  mediaPreview: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 6, backgroundColor: '#FFF', borderTopWidth: 1, borderTopColor: '#F0ECE5' },
  previewImg: { width: 56, height: 56, borderRadius: 10 },
  previewVid: { width: 56, height: 56, borderRadius: 10, backgroundColor: '#1B4332', justifyContent: 'center', alignItems: 'center' },
  previewVidText: { fontSize: 8, color: '#FFF', marginTop: 2 },
  removeMedia: { marginLeft: 8, padding: 4 },
  // Recording
  recordingBar: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingHorizontal: 16, paddingVertical: 12, backgroundColor: '#FFF', borderTopWidth: 1, borderTopColor: '#F0ECE5' },
  cancelRecBtn: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#FEF2F2', justifyContent: 'center', alignItems: 'center' },
  recDot: { width: 10, height: 10, borderRadius: 5, backgroundColor: '#EF4444' },
  recTime: { fontSize: 15, fontWeight: '700', color: '#1B4332', fontVariant: ['tabular-nums'] },
  recLabel: { flex: 1, fontSize: 13, color: '#9CA3AF' },
  sendRecBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#2D6A4F', justifyContent: 'center', alignItems: 'center' },
  // Input
  inputBar: { flexDirection: 'row', alignItems: 'flex-end', paddingHorizontal: 10, paddingVertical: 8, borderTopWidth: 1, borderTopColor: '#F0ECE5', backgroundColor: '#FFF', gap: 6 },
  attachBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  input: { flex: 1, backgroundColor: '#F3F0EB', borderRadius: 20, paddingHorizontal: 16, paddingVertical: 10, fontSize: 15, color: '#1B4332', maxHeight: 100 },
  sendBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#2D6A4F', justifyContent: 'center', alignItems: 'center' },
  micBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  // Attach
  attachOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.3)', justifyContent: 'flex-end' },
  attachSheet: { backgroundColor: '#FFF', borderTopLeftRadius: 24, borderTopRightRadius: 24, paddingHorizontal: 24, paddingBottom: 40, paddingTop: 12 },
  attachHandle: { width: 40, height: 4, backgroundColor: '#D1D5DB', borderRadius: 2, alignSelf: 'center', marginBottom: 16 },
  attachTitle: { fontSize: 18, fontWeight: '700', color: '#1B4332', marginBottom: 20, textAlign: 'center' },
  attachOpts: { flexDirection: 'row', justifyContent: 'space-around' },
  attachOpt: { alignItems: 'center', gap: 8 },
  attachIconBox: { width: 60, height: 60, borderRadius: 20, justifyContent: 'center', alignItems: 'center' },
  attachLabel: { fontSize: 13, fontWeight: '600', color: '#374151' },
  // Viewer
  viewerOverlay: { flex: 1, backgroundColor: 'rgba(0,0,0,0.95)', justifyContent: 'center', alignItems: 'center' },
  closeViewer: { position: 'absolute', top: 50, right: 20, zIndex: 10, width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  fullImg: { width: SW, height: SW },
});
