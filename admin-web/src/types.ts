export type AdminRole = 'owner' | 'admin' | 'moderator' | 'support' | 'viewer';

export type AdminUser = {
  id: string;
  username: string | null;
  raw_username?: string;
  full_name: string;
  email?: string;
  phone?: string;
  profile_image?: string;
  bio?: string;
  city?: string;
  status: string;
  suspended_until?: string | null;
  banned_at?: string | null;
  ban_reason?: string;
  warning_count?: number;
  followers_count?: number;
  following_count?: number;
  posts_count?: number;
  report_count?: number;
  is_admin?: boolean;
  is_creator?: boolean;
  is_verified?: boolean;
  created_at?: string;
  updated_at?: string;
};

export type AdminSession = {
  user: AdminUser;
  role: AdminRole;
  permissions: string[];
  environment: string;
};

export type DashboardResponse = {
  cards: Record<string, number>;
  queues: {
    new_reports: ReportSummary[];
  };
};

export type ReportSummary = {
  id: string;
  reporter_id: string;
  reported_id: string;
  target_type: string;
  target_id: string;
  target_owner_user_id?: string;
  reason: string;
  details: string;
  status: string;
  priority: string;
  created_at: string;
  updated_at: string;
  closed_at?: string | null;
  reporter: UserMini;
  target_user: UserMini;
  preview: string;
  target_media?: AdminMedia | null;
};

export type UserMini = {
  id: string;
  username: string | null;
  full_name: string;
  profile_image?: string;
  status?: string;
};

export type ReportDetail = ReportSummary & {
  admin_notes?: string;
  action_taken?: string;
  reviewed_by?: string;
  reviewed_at?: string | null;
  target?: Record<string, unknown>;
  notes?: Array<{
    id: string;
    note: string;
    created_at: string;
    admin: UserMini;
  }>;
  previous_actions?: AuditLog[];
};

export type AdminPost = {
  id: string;
  user_id: string;
  author: UserMini;
  title?: string;
  content: string;
  category: string;
  visibility: string;
  status: string;
  removed_at?: string | null;
  removed_reason?: string;
  discover_blocked_at?: string | null;
  discover_blocked_reason?: string;
  image?: string;
  images?: string[];
  media_type?: string;
  feed_media_url?: string;
  thumbnail_url?: string;
  poster_url?: string;
  feed_media_urls?: string[];
  thumbnail_urls?: string[];
  poster_urls?: string[];
  media_types?: string[];
  width?: number | null;
  height?: number | null;
  aspect_ratio?: number | null;
  media?: AdminMedia[];
  likes_count?: number;
  comments_count?: number;
  saves_count?: number;
  created_at?: string;
  updated_at?: string;
};

export type AdminMedia = {
  type?: string;
  media_type?: string;
  feed_media_url?: string;
  feedUrl?: string;
  thumbnail_url?: string;
  thumbnailUrl?: string;
  poster_url?: string;
  posterUrl?: string;
  width?: number | null;
  height?: number | null;
  aspect_ratio?: number | null;
  aspectRatio?: number | null;
};

export type AdminComment = {
  id: string;
  user_id: string;
  post_id: string;
  parent_id?: string | null;
  content: string;
  status: string;
  removed_at?: string | null;
  removed_reason?: string;
  hidden_at?: string | null;
  likes_count?: number;
  author: UserMini;
  post_author_id?: string;
  created_at?: string;
};

export type AuditLog = {
  id: string;
  actor_admin_user_id?: string;
  actor_role?: string;
  actor_username?: string | null;
  actor_full_name?: string;
  action_type: string;
  target_type: string;
  target_id: string;
  target_user_id?: string;
  reason?: string;
  internal_note?: string;
  note?: string;
  created_at: string;
};

export type Paginated<T> = {
  results: T[];
  pagination?: {
    limit: number;
    offset: number;
    next_offset: number;
  };
};

export type ReportedMessageDetail = {
  report: ReportDetail;
  privacy_warning: string;
  context: Array<{
    id: string;
    sender_id: string;
    receiver_id: string;
    content: string;
    media_type?: string;
    status: string;
    created_at: string;
    is_reported: boolean;
  }>;
};
