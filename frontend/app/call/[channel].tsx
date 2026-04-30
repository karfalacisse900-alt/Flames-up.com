import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Image,
  PermissionsAndroid,
  Platform,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { Ionicons } from '@expo/vector-icons';
import { useLocalSearchParams, useRouter } from 'expo-router';
import api from '../../src/api/client';
import { loadAgoraModule } from '../../src/utils/agora';
import type { CallMode, CallRole } from '../../src/utils/calls';

type TokenResponse = {
  appId?: string;
  channel: string;
  uid: number;
  role: CallRole;
  mode: CallMode;
  token: string;
  expires_in: number;
  expires_at: string;
};

function readParam(value?: string | string[]): string {
  return Array.isArray(value) ? value[0] || '' : value || '';
}

async function requestNativeCallPermissions(): Promise<boolean> {
  if (Platform.OS !== 'android') return true;

  const result = await PermissionsAndroid.requestMultiple([
    PermissionsAndroid.PERMISSIONS.CAMERA,
    PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
  ]);

  return (
    result[PermissionsAndroid.PERMISSIONS.CAMERA] === PermissionsAndroid.RESULTS.GRANTED &&
    result[PermissionsAndroid.PERMISSIONS.RECORD_AUDIO] === PermissionsAndroid.RESULTS.GRANTED
  );
}

export default function AgoraCallScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{
    channel?: string;
    peerName?: string;
    peerAvatar?: string;
    mode?: CallMode;
    role?: CallRole;
  }>();

  const channel = readParam(params.channel);
  const peerName = readParam(params.peerName) || 'Video call';
  const peerAvatar = readParam(params.peerAvatar);
  const mode = (readParam(params.mode) === 'live' ? 'live' : 'call') as CallMode;
  const role = (readParam(params.role) === 'audience' ? 'audience' : 'host') as CallRole;

  const agora = useMemo(() => loadAgoraModule(), []);
  const engineRef = useRef<any>(null);
  const tokenRef = useRef<TokenResponse | null>(null);
  const closedRef = useRef(false);
  const [localUid, setLocalUid] = useState<number | null>(null);
  const [remoteUid, setRemoteUid] = useState<number | null>(null);
  const [isJoining, setIsJoining] = useState(true);
  const [isJoined, setIsJoined] = useState(false);
  const [micMuted, setMicMuted] = useState(false);
  const [cameraOff, setCameraOff] = useState(false);
  const [usingFrontCamera, setUsingFrontCamera] = useState(true);
  const [elapsed, setElapsed] = useState(0);
  const [statusText, setStatusText] = useState('Connecting...');
  const [errorText, setErrorText] = useState('');

  const RtcSurfaceView = agora?.RtcSurfaceView;

  const fetchToken = useCallback(async (): Promise<TokenResponse> => {
    const response = await api.post('/calls/agora/token', { channel, role, mode });
    tokenRef.current = response.data;
    return response.data;
  }, [channel, mode, role]);

  const cleanupEngine = useCallback(() => {
    const engine = engineRef.current;
    engineRef.current = null;
    if (!engine) return;

    try { engine.leaveChannel(); } catch {}
    try { engine.stopPreview(); } catch {}
    try { engine.release(); } catch {}
  }, []);

  const endCall = useCallback(() => {
    closedRef.current = true;
    cleanupEngine();
    router.back();
  }, [cleanupEngine, router]);

  useEffect(() => {
    let mounted = true;

    async function joinCall() {
      try {
        if (!agora || !RtcSurfaceView) {
          setIsJoining(false);
          setStatusText('Video calls need an iOS or Android development build.');
          return;
        }

        const granted = await requestNativeCallPermissions();
        if (!granted) {
          setIsJoining(false);
          setErrorText('Camera and microphone access are required for video calls.');
          return;
        }

        const tokenData = await fetchToken();
        const appId = (process.env.EXPO_PUBLIC_AGORA_APP_ID || tokenData.appId || '').trim();
        if (!appId) {
          throw new Error('Missing EXPO_PUBLIC_AGORA_APP_ID');
        }

        const channelProfile = mode === 'live'
          ? agora.ChannelProfileType.ChannelProfileLiveBroadcasting
          : agora.ChannelProfileType.ChannelProfileCommunication;
        const clientRole = role === 'audience'
          ? agora.ClientRoleType.ClientRoleAudience
          : agora.ClientRoleType.ClientRoleBroadcaster;

        const engine = agora.createAgoraRtcEngine();
        engineRef.current = engine;
        engine.initialize({ appId, channelProfile });
        engine.registerEventHandler({
          onJoinChannelSuccess: (connection: { localUid?: number }) => {
            if (!mounted) return;
            setLocalUid(connection?.localUid || tokenData.uid);
            setIsJoined(true);
            setIsJoining(false);
            setStatusText(mode === 'live' && role === 'audience' ? 'Watching' : 'Waiting for them to join...');
          },
          onUserJoined: (_connection: unknown, uid: number) => {
            if (!mounted) return;
            setRemoteUid(uid);
            setStatusText('Connected');
          },
          onUserOffline: (_connection: unknown, uid: number) => {
            if (!mounted) return;
            setRemoteUid((current) => (current === uid ? null : current));
            setStatusText('They left the call');
          },
          onError: (err: number, message: string) => {
            if (!mounted) return;
            setErrorText(`Agora error ${err}${message ? `: ${message}` : ''}`);
            setIsJoining(false);
          },
          onTokenPrivilegeWillExpire: async () => {
            try {
              const renewed = await fetchToken();
              engine.renewToken(renewed.token);
            } catch {}
          },
        });

        engine.setChannelProfile(channelProfile);
        engine.setClientRole(clientRole);
        engine.enableVideo();
        if (clientRole === agora.ClientRoleType.ClientRoleBroadcaster) {
          engine.startPreview();
        }
        engine.joinChannel(tokenData.token, tokenData.channel, tokenData.uid, {
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
          channelProfile,
          clientRoleType: clientRole,
          publishCameraTrack: clientRole === agora.ClientRoleType.ClientRoleBroadcaster,
          publishMicrophoneTrack: clientRole === agora.ClientRoleType.ClientRoleBroadcaster,
        });
      } catch (error: any) {
        if (!mounted) return;
        setIsJoining(false);
        setErrorText(error?.response?.data?.detail || error?.message || 'Could not start the call.');
      }
    }

    joinCall();

    return () => {
      mounted = false;
      if (!closedRef.current) cleanupEngine();
    };
  }, [agora, cleanupEngine, fetchToken, mode, role, RtcSurfaceView]);

  useEffect(() => {
    if (!isJoined) return undefined;
    const timer = setInterval(() => setElapsed((value) => value + 1), 1000);
    return () => clearInterval(timer);
  }, [isJoined]);

  const toggleMic = () => {
    const next = !micMuted;
    setMicMuted(next);
    engineRef.current?.muteLocalAudioStream(next);
  };

  const toggleCamera = () => {
    const next = !cameraOff;
    setCameraOff(next);
    engineRef.current?.muteLocalVideoStream(next);
    if (next) {
      engineRef.current?.stopPreview();
    } else {
      engineRef.current?.startPreview();
    }
  };

  const flipCamera = () => {
    engineRef.current?.switchCamera();
    setUsingFrontCamera((value) => !value);
  };

  const durationLabel = `${Math.floor(elapsed / 60)}:${String(elapsed % 60).padStart(2, '0')}`;
  const isAudience = mode === 'live' && role === 'audience';

  return (
    <View style={styles.root}>
      <StatusBar style="light" />
      <View style={styles.remoteLayer}>
        {remoteUid && RtcSurfaceView ? (
          <RtcSurfaceView
            style={StyleSheet.absoluteFill}
            canvas={{ uid: remoteUid, renderMode: agora?.RenderModeType.RenderModeHidden }}
          />
        ) : (
          <View style={styles.waitingState}>
            {peerAvatar ? (
              <Image source={{ uri: peerAvatar }} style={styles.waitingAvatar} />
            ) : (
              <View style={styles.waitingAvatarFallback}>
                <Text style={styles.waitingInitial}>{peerName[0]?.toUpperCase() || 'F'}</Text>
              </View>
            )}
            <Text style={styles.waitingName}>{peerName}</Text>
            <Text style={styles.waitingStatus}>{errorText || statusText}</Text>
            {isJoining && <ActivityIndicator color="#FFFFFF" style={styles.spinner} />}
          </View>
        )}
      </View>

      <SafeAreaView pointerEvents="box-none" style={styles.overlay}>
        <View style={styles.topBar}>
          <TouchableOpacity style={styles.topButton} onPress={endCall} activeOpacity={0.82}>
            <Ionicons name="chevron-down" size={24} color="#FFF" />
          </TouchableOpacity>
          <View style={styles.callMeta}>
            <Text style={styles.peerName} numberOfLines={1}>{peerName}</Text>
            <Text style={styles.callStatus}>{remoteUid ? durationLabel : statusText}</Text>
          </View>
          <TouchableOpacity style={styles.topButton} activeOpacity={0.82}>
            <Ionicons name="ellipsis-horizontal" size={22} color="#FFF" />
          </TouchableOpacity>
        </View>

        {!isAudience && (
          <View style={styles.localPreview}>
            {!cameraOff && RtcSurfaceView ? (
              <RtcSurfaceView
                style={StyleSheet.absoluteFill}
                zOrderMediaOverlay
                canvas={{ uid: localUid || 0, renderMode: agora?.RenderModeType.RenderModeHidden }}
              />
            ) : (
              <View style={styles.localCameraOff}>
                <Ionicons name="videocam-off" size={24} color="#FFF" />
              </View>
            )}
            <View style={styles.localBadge}>
              <Text style={styles.localBadgeText}>{usingFrontCamera ? 'Front' : 'Back'}</Text>
            </View>
          </View>
        )}

        <View style={styles.controlsBar}>
          {!isAudience && (
            <>
              <TouchableOpacity style={[styles.controlButton, micMuted && styles.controlActive]} onPress={toggleMic} activeOpacity={0.85}>
                <Ionicons name={micMuted ? 'mic-off' : 'mic'} size={24} color="#FFF" />
              </TouchableOpacity>
              <TouchableOpacity style={[styles.controlButton, cameraOff && styles.controlActive]} onPress={toggleCamera} activeOpacity={0.85}>
                <Ionicons name={cameraOff ? 'videocam-off' : 'videocam'} size={24} color="#FFF" />
              </TouchableOpacity>
              <TouchableOpacity style={styles.controlButton} onPress={flipCamera} activeOpacity={0.85}>
                <Ionicons name="camera-reverse" size={24} color="#FFF" />
              </TouchableOpacity>
            </>
          )}
          <TouchableOpacity style={styles.endButton} onPress={endCall} activeOpacity={0.85}>
            <Ionicons name="call" size={25} color="#FFF" style={styles.endIcon} />
          </TouchableOpacity>
        </View>

        {errorText ? (
          <TouchableOpacity
            style={styles.errorPill}
            activeOpacity={0.9}
            onPress={() => Alert.alert('Video call', errorText)}
          >
            <Ionicons name="alert-circle" size={16} color="#FFF" />
            <Text style={styles.errorPillText} numberOfLines={2}>{errorText}</Text>
          </TouchableOpacity>
        ) : null}
      </SafeAreaView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#050607',
  },
  remoteLayer: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: '#050607',
  },
  overlay: {
    flex: 1,
    justifyContent: 'space-between',
  },
  topBar: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 16,
    paddingTop: 8,
  },
  topButton: {
    width: 42,
    height: 42,
    borderRadius: 21,
    backgroundColor: 'rgba(255,255,255,0.18)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  callMeta: {
    flex: 1,
    alignItems: 'center',
    paddingHorizontal: 12,
  },
  peerName: {
    color: '#FFFFFF',
    fontSize: 17,
    fontWeight: '700',
  },
  callStatus: {
    color: 'rgba(255,255,255,0.72)',
    fontSize: 12,
    marginTop: 2,
  },
  waitingState: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 28,
  },
  waitingAvatar: {
    width: 112,
    height: 112,
    borderRadius: 56,
    marginBottom: 18,
  },
  waitingAvatarFallback: {
    width: 112,
    height: 112,
    borderRadius: 56,
    backgroundColor: '#263F2A',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: 18,
  },
  waitingInitial: {
    color: '#FFFFFF',
    fontSize: 42,
    fontWeight: '800',
  },
  waitingName: {
    color: '#FFFFFF',
    fontSize: 26,
    fontWeight: '800',
    textAlign: 'center',
  },
  waitingStatus: {
    color: 'rgba(255,255,255,0.72)',
    fontSize: 15,
    textAlign: 'center',
    marginTop: 10,
    lineHeight: 20,
  },
  spinner: {
    marginTop: 18,
  },
  localPreview: {
    position: 'absolute',
    top: 104,
    right: 16,
    width: 112,
    height: 158,
    borderRadius: 18,
    overflow: 'hidden',
    backgroundColor: '#1C1C1E',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.24)',
  },
  localCameraOff: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#263F2A',
  },
  localBadge: {
    position: 'absolute',
    left: 8,
    bottom: 8,
    borderRadius: 10,
    backgroundColor: 'rgba(0,0,0,0.45)',
    paddingHorizontal: 7,
    paddingVertical: 3,
  },
  localBadgeText: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '700',
  },
  controlsBar: {
    alignSelf: 'center',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 14,
    marginBottom: 24,
    borderRadius: 38,
    backgroundColor: 'rgba(14,14,16,0.72)',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  controlButton: {
    width: 56,
    height: 56,
    borderRadius: 28,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(255,255,255,0.18)',
  },
  controlActive: {
    backgroundColor: 'rgba(255,255,255,0.34)',
  },
  endButton: {
    width: 60,
    height: 60,
    borderRadius: 30,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#EF4444',
  },
  endIcon: {
    transform: [{ rotate: '135deg' }],
  },
  errorPill: {
    position: 'absolute',
    left: 18,
    right: 18,
    bottom: 108,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    borderRadius: 14,
    paddingHorizontal: 12,
    paddingVertical: 10,
    backgroundColor: 'rgba(239,68,68,0.86)',
  },
  errorPillText: {
    flex: 1,
    color: '#FFFFFF',
    fontSize: 13,
    fontWeight: '600',
  },
});
