import React, { useEffect, useMemo, useState } from 'react';
import { Image as ExpoImage, type ImageProps } from 'expo-image';
import type { ImageResizeMode } from 'react-native';
import { makeMediaCacheKey } from '../../modules/mira-performance';
import { optimizeImageUrl, type OptimizedImagePreset } from '../utils/optimizedMedia';

type OptimizedImageProps = Omit<ImageProps, 'source' | 'resizeMode'> & {
  uri?: string | null;
  source?: ImageProps['source'];
  preset?: OptimizedImagePreset;
  resizeMode?: ImageResizeMode;
};

function fitFromResizeMode(resizeMode?: ImageResizeMode): ImageProps['contentFit'] {
  if (resizeMode === 'contain') return 'contain';
  if (resizeMode === 'stretch') return 'fill';
  if (resizeMode === 'center') return 'scale-down';
  return 'cover';
}

function sourceUri(source: ImageProps['source'] | undefined): string {
  if (!source || typeof source !== 'object' || Array.isArray(source)) return '';
  const uri = (source as { uri?: unknown }).uri;
  return typeof uri === 'string' ? uri : '';
}

function OptimizedImage({
  uri,
  source,
  preset = 'feed',
  resizeMode,
  contentFit,
  cachePolicy = 'memory-disk',
  transition = 80,
  recyclingKey,
  onError,
  ...props
}: OptimizedImageProps) {
  const originalUri = uri || sourceUri(source);
  const optimizedUri = useMemo(() => optimizeImageUrl(originalUri, preset), [originalUri, preset]);
  const stableRecyclingKey = useMemo(
    () => (originalUri ? makeMediaCacheKey(originalUri, 0, 0, preset) : undefined),
    [originalUri, preset]
  );
  const [useOriginal, setUseOriginal] = useState(false);

  useEffect(() => {
    setUseOriginal(false);
  }, [optimizedUri, originalUri]);

  const finalSource = originalUri
    ? { uri: useOriginal ? originalUri : optimizedUri }
    : source;

  return (
    <ExpoImage
      {...props}
      source={finalSource}
      contentFit={contentFit || fitFromResizeMode(resizeMode)}
      cachePolicy={cachePolicy}
      transition={transition}
      recyclingKey={recyclingKey || stableRecyclingKey}
      onError={(event) => {
        if (!useOriginal && optimizedUri && optimizedUri !== originalUri) {
          setUseOriginal(true);
          return;
        }
        onError?.(event);
      }}
    />
  );
}

export default React.memo(OptimizedImage);
