import type { ImagePickerAsset } from 'expo-image-picker';
import { createMediaProcessingPlan, type MediaProcessingPlan } from '../native/mediaEngine';

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
  processingPlan?: MediaProcessingPlan;
};

function dataUriFromAsset(asset: ImagePickerAsset, mimeType: string): string | undefined {
  if (!asset.base64) return undefined;
  return asset.base64.startsWith('data:') ? asset.base64 : `data:${mimeType};base64,${asset.base64}`;
}

export async function processMediaAsset(
  asset: ImagePickerAsset,
  preset: MediaProcessingPreset = 'balanced'
): Promise<ProcessedMediaAsset> {
  const normalizedType: 'image' | 'video' = asset.type === 'video' ? 'video' : 'image';
  const processingPlan = createMediaProcessingPlan({
    uri: asset.uri,
    mimeType: asset.mimeType || undefined,
    fileName: asset.fileName || undefined,
    fileSize: asset.fileSize,
    width: asset.width || undefined,
    height: asset.height || undefined,
    preset,
  });

  if (normalizedType === 'video') {
    return {
      uri: asset.uri,
      type: 'video',
      width: asset.width || undefined,
      height: asset.height || undefined,
      mimeType: asset.mimeType || 'video/mp4',
      fileName: asset.fileName || null,
      fileSize: asset.fileSize,
      processingPlan,
    };
  }

  const mimeType = asset.mimeType || 'image/jpeg';
  const dataUri = dataUriFromAsset(asset, mimeType);

  return {
    uri: asset.uri,
    type: 'image',
    base64: dataUri,
    width: asset.width || undefined,
    height: asset.height || undefined,
    mimeType,
    fileName: asset.fileName || null,
    fileSize: asset.fileSize,
    processingPlan,
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

