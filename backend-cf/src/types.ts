export interface Env {
  DB: D1Database;
  KV: KVNamespace;
  HYPERDRIVE?: any;
  AI?: any;
  MEDIA_MODERATION_QUEUE?: Queue<{
    jobId: string;
    mediaId: string;
    userId: string;
    reason: 'upload_complete' | 'manual_retry' | 'admin_retry';
    caption?: string;
  }>;
  MEDIA_BACKUP?: R2Bucket;
  JWT_SECRET: string;
  CF_API_TOKEN?: string;
  CF_ACCOUNT_ID?: string;
  CF_ACCOUNT_HASH?: string;
  CLOUDFLARE_ACCOUNT_ID?: string;
  CLOUDFLARE_API_TOKEN?: string;
  CLOUDFLARE_IMAGES_ACCOUNT_HASH?: string;
  CLOUDFLARE_IMAGES_TOKEN?: string;
  CLOUDFLARE_IMAGES_FEED_VARIANT?: string;
  CLOUDFLARE_IMAGES_THUMBNAIL_VARIANT?: string;
  CLOUDFLARE_IMAGE_TRANSFORMS_ENABLED?: string;
  CLOUDFLARE_IMAGE_TRANSFORM_BASE_URL?: string;
  CLOUDFLARE_STREAM_TOKEN?: string;
  AI_IMAGE_MODERATION_MODEL?: string;
  AI_TEXT_MODERATION_MODEL?: string;
  AI_GENERATED_MEDIA_POLICY?: string;
  MALWARE_SCANNER_URL?: string;
  MALWARE_SCANNER_TOKEN?: string;
  MEDIA_MAX_IMAGE_BYTES?: string;
  MEDIA_MAX_VIDEO_BYTES?: string;
  MAPBOX_ACCESS_TOKEN?: string;
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
  GIPHY_API_KEY?: string;
  AGORA_APP_ID?: string;
  AGORA_APP_CERTIFICATE?: string;
  AGORA_TOKEN_TTL_SECONDS?: string;
  APNS_TEAM_ID?: string;
  APNS_KEY_ID?: string;
  APNS_BUNDLE_ID?: string;
  APNS_PRIVATE_KEY?: string;
  APNS_VOIP_PRIVATE_KEY?: string;
  APNS_ENVIRONMENT?: string;
  MEDIA_BACKUP_MAX_VIDEO_BYTES?: string;
  STRIPE_SECRET_KEY?: string;
  STRIPE_PUBLISHABLE_KEY?: string;
  STRIPE_DEFAULT_PRICE_ID?: string;
  STRIPE_PREMIUM_PRICE_ID?: string;
  STRIPE_SUCCESS_URL?: string;
  STRIPE_CANCEL_URL?: string;
  STRIPE_WEBHOOK_SECRET?: string;
  SUPABASE_URL?: string;
  SUPABASE_ANON_KEY?: string;
  SUPABASE_JWT_ISSUER?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  ABUSE_SIGNAL_SECRET?: string;
  OWNERSHIP_ANCHOR_PROVIDER?: string;
  EVM_RPC_URL?: string;
  EVM_CONTRACT_ADDRESS?: string;
  SOLANA_RPC_URL?: string;
  IPFS_API_URL?: string;
  ARWEAVE_GATEWAY?: string;
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
