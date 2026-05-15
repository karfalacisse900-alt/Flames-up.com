export type MiraPerformanceModuleShape = {
  nativeRuntime?: string;
  makeMediaCacheKey?: (uri: string, width: number, height: number, preset: string) => string;
  planMedia?: (
    uri: string,
    mimeType: string,
    fileName: string,
    fileSize: number,
    width: number,
    height: number,
    preset: string
  ) => string;
  nativeDesignProfile?: () => string;
  scoreFeedItem?: (
    likes: number,
    comments: number,
    saves: number,
    shares: number,
    views: number,
    ageHours: number,
    isFollowed: boolean,
    isVideo: boolean
  ) => number;
};

export type MiraMediaPlan = {
  kind: 'image' | 'video' | 'unknown';
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

export type MiraNativeDesignProfile = {
  runtime: string;
  platform: string;
  surface: string;
  surfaceSoft: string;
  textPrimary: string;
  textSecondary: string;
  forest: string;
  forestPressed: string;
  shadowColor: string;
  shadowOpacity: number;
  radiusCard: number;
  radiusSheet: number;
  minTouchTarget: number;
};
