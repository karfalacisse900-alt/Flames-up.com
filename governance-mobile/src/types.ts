export type FilterStatus = 'pending' | 'resolved' | 'dismissed' | 'all';

export type AdminUser = {
  id: string;
  email?: string;
  username?: string;
  full_name?: string;
  profile_image?: string;
  is_admin: boolean;
};

export type GovernanceStats = {
  active_users: number;
  pending_reports: number;
  banned_users: number;
  removed_posts: number;
};

export type GovernanceReport = {
  id: string;
  reporter_id: string;
  reported_id?: string;
  reported_type?: string;
  report_type?: string;
  reason?: string;
  details?: string;
  content_id?: string;
  status: FilterStatus;
  admin_notes?: string;
  action_taken?: string;
  reviewed_by?: string;
  created_at?: string;
  updated_at?: string;
  reporter_username?: string;
  reporter_full_name?: string;
  reporter_profile_image?: string;
  target_username?: string;
  target_full_name?: string;
  target_profile_image?: string;
  target_status?: string;
  post_id?: string;
  post_user_id?: string;
  post_content?: string;
  post_image?: string;
  post_images?: string[];
  post_media_types?: string[];
  post_status?: string;
  post_author_username?: string;
  post_author_full_name?: string;
};
