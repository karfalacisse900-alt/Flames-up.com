import React, { useEffect, useMemo, useState } from 'react';
import {
  ImageResizeMode,
  StyleProp,
  StyleSheet,
  View,
  ViewStyle,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { extractStreamUid, getStreamPlaybackInfo, isCFStreamVideo } from '../utils/mediaUpload';
import OptimizedImage from './OptimizedImage';
import { getStreamThumbnailUrl, type OptimizedImagePreset } from '../utils/optimizedMedia';
import { colors } from '../utils/theme';

type MediaPreviewProps = {
  uri?: string | null;
  mediaTypes?: string[] | string | null;
  style?: StyleProp<ViewStyle>;
  resizeMode?: ImageResizeMode;
  showVideoBadge?: boolean;
  imagePreset?: OptimizedImagePreset;
  priority?: 'low' | 'normal' | 'high';
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
  return getStreamThumbnailUrl(videoUid, 'thumb');
}

function MediaPreview({
  uri,
  mediaTypes,
  style,
  resizeMode = 'cover',
  showVideoBadge = true,
  imagePreset = 'feed',
  priority = 'normal',
}: MediaPreviewProps) {
  const cleanUri = typeof uri === 'string' ? uri.trim() : '';
  const streamUid = useMemo(() => (
    cleanUri && isCFStreamVideo(cleanUri) ? extractStreamUid(cleanUri) : ''
  ), [cleanUri]);
  const isVideo = isVideoUri(cleanUri, mediaTypes);
  const fallbackUri = streamUid ? getStreamThumbnailFallback(streamUid) : cleanUri;
  const [previewUri, setPreviewUri] = useState(fallbackUri);

  useEffect(() => {
    let mounted = true;
    setPreviewUri(fallbackUri);

    if (!streamUid) return () => { mounted = false; };

    getStreamPlaybackInfo(streamUid)
      .then((info) => {
        if (!mounted) return;
        if (info?.thumbnail) setPreviewUri(info.thumbnail);
      })
      .catch(() => undefined);

    return () => {
      mounted = false;
    };
  }, [fallbackUri, streamUid]);

  return (
    <View style={[styles.wrap, style]}>
      {previewUri ? (
        isVideo && !streamUid && !/\.(jpe?g|png|webp|gif|heic|heif|avif)(\?.*)?$/i.test(previewUri) ? (
          <View style={styles.empty}>
            <Ionicons name="videocam-outline" size={24} color="#9CA3AF" />
          </View>
        ) : (
          <OptimizedImage
            uri={previewUri}
            preset={streamUid ? 'thumb' : imagePreset}
            style={styles.image}
            resizeMode={resizeMode}
            priority={priority}
          />
        )
      ) : (
        <View style={styles.empty}>
          <Ionicons name={isVideo ? 'videocam-outline' : 'image-outline'} size={24} color="#9CA3AF" />
        </View>
      )}
      {isVideo && showVideoBadge ? (
        <View style={styles.badge}>
          <Ionicons name="play" size={13} color="#FFFFFF" />
        </View>
      ) : null}
    </View>
  );
}

export default React.memo(MediaPreview);

const styles = StyleSheet.create({
  wrap: {
    overflow: 'hidden',
    backgroundColor: colors.bgSubtle,
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
    backgroundColor: colors.bgSubtle,
  },
  badge: {
    position: 'absolute',
    right: 8,
    top: 8,
    width: 28,
    height: 28,
    borderRadius: 14,
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'rgba(17,18,14,0.66)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.28)',
  },
});
