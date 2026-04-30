import React, { useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Image,
  ImageResizeMode,
  StyleProp,
  StyleSheet,
  View,
  ViewStyle,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { extractStreamUid, getStreamPlaybackInfo, isCFStreamVideo } from '../utils/mediaUpload';

type MediaPreviewProps = {
  uri?: string | null;
  mediaTypes?: string[] | string | null;
  style?: StyleProp<ViewStyle>;
  resizeMode?: ImageResizeMode;
  showVideoBadge?: boolean;
};

function normalizeMediaTypes(mediaTypes?: string[] | string | null): string[] {
  if (Array.isArray(mediaTypes)) return mediaTypes.map((item) => String(item).toLowerCase());
  if (typeof mediaTypes === 'string') {
    try {
      const parsed = JSON.parse(mediaTypes);
      if (Array.isArray(parsed)) return parsed.map((item) => String(item).toLowerCase());
    } catch {}
    return mediaTypes.split(',').map((item) => item.trim().toLowerCase()).filter(Boolean);
  }
  return [];
}

function isVideoUri(uri?: string | null, mediaTypes?: string[] | string | null) {
  if (!uri) return false;
  if (isCFStreamVideo(uri)) return true;
  const types = normalizeMediaTypes(mediaTypes);
  if (types.some((type) => type.includes('video'))) return true;
  return /\.(mp4|mov|m4v|webm)(\?.*)?$/i.test(uri);
}

export function getStreamThumbnailFallback(videoUid: string) {
  return `https://videodelivery.net/${videoUid}/thumbnails/thumbnail.jpg?time=1s&height=720`;
}

export default function MediaPreview({
  uri,
  mediaTypes,
  style,
  resizeMode = 'cover',
  showVideoBadge = true,
}: MediaPreviewProps) {
  const cleanUri = typeof uri === 'string' ? uri.trim() : '';
  const streamUid = useMemo(() => (
    cleanUri && isCFStreamVideo(cleanUri) ? extractStreamUid(cleanUri) : ''
  ), [cleanUri]);
  const isVideo = isVideoUri(cleanUri, mediaTypes);
  const fallbackUri = streamUid ? getStreamThumbnailFallback(streamUid) : cleanUri;
  const [previewUri, setPreviewUri] = useState(fallbackUri);
  const [loadingStreamInfo, setLoadingStreamInfo] = useState(!!streamUid);

  useEffect(() => {
    let mounted = true;
    setPreviewUri(fallbackUri);
    setLoadingStreamInfo(!!streamUid);

    if (!streamUid) return () => { mounted = false; };

    getStreamPlaybackInfo(streamUid)
      .then((info) => {
        if (!mounted) return;
        if (info?.thumbnail) setPreviewUri(info.thumbnail);
      })
      .finally(() => {
        if (mounted) setLoadingStreamInfo(false);
      });

    return () => {
      mounted = false;
    };
  }, [fallbackUri, streamUid]);

  return (
    <View style={[styles.wrap, style]}>
      {previewUri ? (
        <Image source={{ uri: previewUri }} style={styles.image} resizeMode={resizeMode} />
      ) : (
        <View style={styles.empty}>
          <Ionicons name={isVideo ? 'videocam-outline' : 'image-outline'} size={24} color="#9CA3AF" />
        </View>
      )}
      {loadingStreamInfo ? (
        <View style={styles.loading}>
          <ActivityIndicator color="#FFFFFF" />
        </View>
      ) : null}
      {isVideo && showVideoBadge ? (
        <View style={styles.badge}>
          <Ionicons name="play" size={13} color="#FFFFFF" />
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: {
    overflow: 'hidden',
    backgroundColor: '#ECECEC',
  },
  image: {
    ...StyleSheet.absoluteFillObject,
    width: '100%',
    height: '100%',
  },
  empty: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#F3F4F6',
  },
  loading: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.18)',
  },
  badge: {
    position: 'absolute',
    right: 8,
    top: 8,
    width: 24,
    height: 24,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(0,0,0,0.58)',
  },
});
