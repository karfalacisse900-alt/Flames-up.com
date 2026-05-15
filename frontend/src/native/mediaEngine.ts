export type MediaKind = 'image' | 'video' | 'unknown';

export type MediaPlanInput = {
  uri?: string | null;
  mimeType?: string | null;
  fileName?: string | null;
  fileSize?: number | null;
  width?: number | null;
  height?: number | null;
  preset?: 'quality' | 'balanced' | 'compact';
};

export type MediaProcessingPlan = {
  kind: MediaKind;
  allowed: boolean;
  reason: string;
  targetWidth: number;
  targetHeight: number;
  aspectRatio: number;
  maxBytes: number;
  targetMimeType: string;
  imageQuality: number;
  videoBitrate: number;
  targetFps: number;
  shouldUseThumbnail: boolean;
  cacheKey: string;
};

type NativeMediaEngine = {
  detectMediaKind?: (uri: string, mimeType?: string, fileName?: string) => MediaKind;
  planMedia?: (input: MediaPlanInput) => string | MediaProcessingPlan;
};

declare global {
  // Installed by the native C++ JSI media engine when available.
  var __FlamesMediaEngine: NativeMediaEngine | undefined;
}

const IMAGE_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'webp', 'heic', 'heif']);
const VIDEO_EXTENSIONS = new Set(['mp4', 'mov', 'm4v', 'webm']);
const UNSAFE_EXTENSIONS = new Set(['apk', 'app', 'bat', 'cmd', 'com', 'dll', 'dmg', 'exe', 'js', 'msi', 'ps1', 'sh', 'svg']);

function extensionFrom(value?: string | null): string {
  const clean = String(value || '').split(/[?#]/)[0].trim().toLowerCase();
  const match = clean.match(/\.([a-z0-9]{1,8})$/);
  return match?.[1] || '';
}

function clampDimension(value: number, fallback: number): number {
  if (!Number.isFinite(value) || value <= 0) return fallback;
  return Math.max(1, Math.round(value));
}

function clampRatio(value: number): number {
  if (!Number.isFinite(value) || value <= 0) return 3 / 4;
  return Math.max(9 / 16, Math.min(1.91, value));
}

function shortHash(value: string): string {
  let hash = 0x811c9dc5;
  for (let i = 0; i < value.length; i += 1) {
    hash = Math.imul(hash ^ value.charCodeAt(i), 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, '0');
}

function parseNativePlan(output: string | MediaProcessingPlan | undefined): MediaProcessingPlan | null {
  if (!output) return null;
  if (typeof output !== 'string') return output;
  try {
    const parsed = JSON.parse(output);
    if (parsed && typeof parsed === 'object') return parsed as MediaProcessingPlan;
  } catch {}
  return null;
}

export function detectMediaKind(input: MediaPlanInput): MediaKind {
  const uri = String(input.uri || '');
  const mime = String(input.mimeType || '').toLowerCase();
  const ext = extensionFrom(input.fileName) || extensionFrom(uri);

  try {
    const nativeKind = global.__FlamesMediaEngine?.detectMediaKind?.(uri, mime, input.fileName || '');
    if (nativeKind === 'image' || nativeKind === 'video' || nativeKind === 'unknown') return nativeKind;
  } catch {}

  if (uri.startsWith('cfstream:') || mime.startsWith('video/') || VIDEO_EXTENSIONS.has(ext)) return 'video';
  if (mime.startsWith('image/') || IMAGE_EXTENSIONS.has(ext) || uri.startsWith('data:image/')) return 'image';
  if (uri.startsWith('data:video/')) return 'video';
  return 'unknown';
}

export function createMediaProcessingPlan(input: MediaPlanInput): MediaProcessingPlan {
  try {
    const nativePlan = parseNativePlan(global.__FlamesMediaEngine?.planMedia?.(input));
    if (nativePlan) return nativePlan;
  } catch {}

  const kind = detectMediaKind(input);
  const ext = extensionFrom(input.fileName) || extensionFrom(input.uri);
  const mime = String(input.mimeType || '').toLowerCase();
  const width = clampDimension(Number(input.width || 0), kind === 'video' ? 1080 : 1440);
  const height = clampDimension(Number(input.height || 0), kind === 'video' ? 1920 : 1920);
  const aspectRatio = clampRatio(width / height);
  const preset = input.preset || 'balanced';
  const maxLongEdge = kind === 'video'
    ? 1920
    : preset === 'quality'
      ? 3000
      : preset === 'compact'
        ? 1280
        : 2200;
  const scale = Math.min(1, maxLongEdge / Math.max(width, height));
  const fileSize = Number(input.fileSize || 0);

  let allowed = kind !== 'unknown';
  let reason = allowed ? 'ok' : 'unknown_media_type';
  if (UNSAFE_EXTENSIONS.has(ext) || mime.includes('svg')) {
    allowed = false;
    reason = 'blocked_unsafe_file_type';
  }

  const maxBytes = kind === 'video' ? 500 * 1024 * 1024 : 20 * 1024 * 1024;
  if (fileSize > maxBytes) {
    allowed = false;
    reason = 'file_too_large';
  }

  const targetMimeType = kind === 'video' ? 'video/mp4' : 'image/jpeg';
  const imageQuality = preset === 'compact' ? 0.84 : preset === 'quality' ? 0.92 : 0.89;
  const videoBitrate = preset === 'compact' ? 5_500_000 : preset === 'quality' ? 12_000_000 : 8_000_000;

  return {
    kind,
    allowed,
    reason,
    targetWidth: Math.max(1, Math.round(width * scale)),
    targetHeight: Math.max(1, Math.round(height * scale)),
    aspectRatio,
    maxBytes,
    targetMimeType,
    imageQuality,
    videoBitrate,
    targetFps: 30,
    shouldUseThumbnail: kind === 'video',
    cacheKey: `${kind}:${shortHash(`${input.uri || ''}|${input.fileName || ''}|${width}x${height}|${fileSize}`)}`,
  };
}
