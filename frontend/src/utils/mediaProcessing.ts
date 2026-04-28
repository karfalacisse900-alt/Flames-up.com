import type { ImagePickerAsset } from 'expo-image-picker';
import { manipulateAsync, SaveFormat, type Action } from 'expo-image-manipulator';

export type MediaProcessingPreset = 'quality' | 'balanced' | 'compact';

export type ProcessedMediaAsset = {
  uri: string;
  type: 'image' | 'video';
  base64?: string;
  width?: number;
  height?: number;
  mimeType?: string;
  fileName?: string | null;
  fileSize?: number;
};

type PresetConfig = {
  maxImageEdge: number;
  compress: number;
};

const PRESET_CONFIGS: Record<MediaProcessingPreset, PresetConfig> = {
  quality: { maxImageEdge: 2200, compress: 0.86 },
  balanced: { maxImageEdge: 1800, compress: 0.72 },
  compact: { maxImageEdge: 1280, compress: 0.58 },
};

function clamp01(value: number): number {
  if (Number.isNaN(value)) return 0.72;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

function buildResizeAction(asset: ImagePickerAsset, maxEdge: number): Action | null {
  const width = asset.width || 0;
  const height = asset.height || 0;
  if (!width || !height) return null;

  const longestEdge = Math.max(width, height);
  if (longestEdge <= maxEdge) return null;

  if (width >= height) {
    return { resize: { width: maxEdge } };
  }
  return { resize: { height: maxEdge } };
}

function approxBytesFromBase64DataUri(dataUri?: string): number | undefined {
  if (!dataUri) return undefined;
  const marker = ';base64,';
  const markerIndex = dataUri.indexOf(marker);
  if (markerIndex === -1) return undefined;
  const base64Payload = dataUri.slice(markerIndex + marker.length);
  return Math.ceil((base64Payload.length * 3) / 4);
}

export async function processMediaAsset(
  asset: ImagePickerAsset,
  preset: MediaProcessingPreset = 'balanced'
): Promise<ProcessedMediaAsset> {
  const normalizedType: 'image' | 'video' = asset.type === 'video' ? 'video' : 'image';
  if (normalizedType === 'video') {
    return {
      uri: asset.uri,
      type: 'video',
      width: asset.width || undefined,
      height: asset.height || undefined,
      mimeType: asset.mimeType || 'video/mp4',
      fileName: asset.fileName || null,
      fileSize: asset.fileSize,
    };
  }

  const cfg = PRESET_CONFIGS[preset] || PRESET_CONFIGS.balanced;
  const resizeAction = buildResizeAction(asset, cfg.maxImageEdge);
  const actions = resizeAction ? [resizeAction] : [];

  const manipulated = await manipulateAsync(asset.uri, actions, {
    compress: clamp01(cfg.compress),
    format: SaveFormat.JPEG,
    base64: true,
  });

  const dataUri = manipulated.base64 ? `data:image/jpeg;base64,${manipulated.base64}` : undefined;

  return {
    uri: manipulated.uri,
    type: 'image',
    base64: dataUri,
    width: manipulated.width || asset.width || undefined,
    height: manipulated.height || asset.height || undefined,
    mimeType: 'image/jpeg',
    fileName: asset.fileName || null,
    fileSize: approxBytesFromBase64DataUri(dataUri) || asset.fileSize,
  };
}

export async function processMediaBatch(
  assets: ImagePickerAsset[],
  preset: MediaProcessingPreset = 'balanced'
): Promise<ProcessedMediaAsset[]> {
  const out: ProcessedMediaAsset[] = [];
  for (const asset of assets) {
    out.push(await processMediaAsset(asset, preset));
  }
  return out;
}

