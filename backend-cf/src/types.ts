export interface Env {
  DB: D1Database;
  KV: KVNamespace;
  JWT_SECRET: string;
  CF_API_TOKEN: string;
  CF_ACCOUNT_ID: string;
  CF_ACCOUNT_HASH: string;
  GOOGLE_MAPS_API_KEY: string;
  ENVIRONMENT: string;
}

export interface User {
  id: string;
  email: string;
  username: string;
  full_name: string;
  hashed_password: string;
  avatar_image_id: string | null;
  bio: string;
  created_at: string;
}

export interface JWTPayload {
  sub: string;
  exp: number;
}
