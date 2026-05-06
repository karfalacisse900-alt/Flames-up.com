export interface Env {
  DB: D1Database;
  KV: KVNamespace;
  MEDIA_BACKUP?: R2Bucket;
  AI?: {
    run: (model: string, input: unknown, options?: unknown) => Promise<unknown>;
  };
  JWT_SECRET: string;
  CF_API_TOKEN: string;
  CF_ACCOUNT_ID: string;
  CF_ACCOUNT_HASH: string;
  CLOUDFLARE_ACCOUNT_ID?: string;
  CLOUDFLARE_IMAGES_ACCOUNT_HASH?: string;
  CLOUDFLARE_IMAGES_TOKEN?: string;
  CLOUDFLARE_STREAM_TOKEN?: string;
  MAPBOX_ACCESS_TOKEN?: string;
  EVENTBRITE_API_TOKEN?: string;
  EVENTS_PREVIEW?: string;
  ENVIRONMENT: string;
  OWNER_USERNAMES?: string;
  GOOGLE_OAUTH_CLIENT_ID?: string;
  GOOGLE_OAUTH_CLIENT_IDS?: string;
  APPLE_OAUTH_AUDIENCE?: string;
  APPLE_OAUTH_AUDIENCES?: string;
  TWILIO_ACCOUNT_SID?: string;
  TWILIO_AUTH_TOKEN?: string;
  TWILIO_VERIFY_SERVICE_SID?: string;
  TWILIO_SERVICE_SID?: string;
  TWILIO_FROM_PHONE?: string;
  AGORA_APP_ID?: string;
  AGORA_APP_CERTIFICATE?: string;
  AGORA_TOKEN_TTL_SECONDS?: string;
  MEDIA_AI_ENHANCEMENT?: string;
  MEDIA_AI_MODEL?: string;
  MEDIA_BACKUP_MAX_VIDEO_BYTES?: string;
}

export interface User {
  id: string;
  email: string;
  phone?: string;
  phone_verified?: number;
  username: string;
  full_name: string;
  hashed_password: string;
  avatar_image_id: string | null;
  bio: string;
  is_private?: number;
  language?: 'en' | 'fr' | 'es';
  created_at: string;
}

export interface JWTPayload {
  sub: string;
  exp: number;
}
