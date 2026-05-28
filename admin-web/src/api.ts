import type {
  AdminComment,
  AdminPost,
  AdminSession,
  AdminUser,
  AuditLog,
  DashboardResponse,
  Paginated,
  ReportDetail,
  ReportedMessageDetail,
  ReportSummary,
} from './types';

const DEFAULT_API_BASE = 'https://api.flames-up.com/api';

export const API_BASE = (import.meta.env.VITE_CAPTRO_API_BASE || DEFAULT_API_BASE).replace(/\/+$/, '');

export class ApiError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

async function request<T>(path: string, token: string, options: RequestInit = {}): Promise<T> {
  const response = await fetch(`${API_BASE}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
      'X-Request-ID': crypto.randomUUID(),
      ...(options.headers || {}),
    },
  });

  const text = await response.text();
  const payload = text ? JSON.parse(text) : {};
  if (!response.ok) {
    throw new ApiError(payload?.detail || 'Request failed', response.status);
  }
  return payload as T;
}

export async function login(email: string, password: string) {
  const response = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Request-ID': crypto.randomUUID() },
    body: JSON.stringify({ email, password }),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new ApiError(payload?.detail || 'Login failed', response.status);
  return payload as { access_token: string };
}

export const AdminApi = {
  me: (token: string) => request<AdminSession>('/admin/me', token),
  health: (token: string) => request<Record<string, string>>('/admin/health', token),
  dashboard: (token: string) => request<DashboardResponse>('/admin/dashboard', token),
  reports: (token: string, query = '') => request<Paginated<ReportSummary>>(`/admin/reports${query}`, token),
  report: (token: string, id: string) => request<{ report: ReportDetail }>(`/admin/reports/${encodeURIComponent(id)}`, token),
  reportStatus: (token: string, id: string, body: Record<string, unknown>) =>
    request<{ report: ReportDetail }>(`/admin/reports/${encodeURIComponent(id)}/status`, token, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  reportAction: (token: string, id: string, body: Record<string, unknown>) =>
    request<{ report: ReportDetail }>(`/admin/reports/${encodeURIComponent(id)}/action`, token, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  reportNote: (token: string, id: string, note: string) =>
    request<{ added: boolean }>(`/admin/reports/${encodeURIComponent(id)}/note`, token, {
      method: 'POST',
      body: JSON.stringify({ note }),
    }),
  users: (token: string, query = '') => request<Paginated<AdminUser>>(`/admin/users${query}`, token),
  user: (token: string, id: string) => request<{ user: AdminUser; restrictions: unknown[]; actions: AuditLog[]; recent_posts: AdminPost[] }>(`/admin/users/${encodeURIComponent(id)}`, token),
  warnUser: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/users/${encodeURIComponent(id)}/warn`, token, { method: 'POST', body: JSON.stringify(body) }),
  restrictUser: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/users/${encodeURIComponent(id)}/restrict`, token, { method: 'POST', body: JSON.stringify(body) }),
  suspendUser: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/users/${encodeURIComponent(id)}/suspend`, token, { method: 'POST', body: JSON.stringify(body) }),
  banUser: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/users/${encodeURIComponent(id)}/ban`, token, { method: 'POST', body: JSON.stringify(body) }),
  unbanUser: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/users/${encodeURIComponent(id)}/unban`, token, { method: 'POST', body: JSON.stringify(body) }),
  forceUsername: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/users/${encodeURIComponent(id)}/force-username-change`, token, { method: 'POST', body: JSON.stringify(body) }),
  posts: (token: string, query = '') => request<Paginated<AdminPost>>(`/admin/posts${query}`, token),
  post: (token: string, id: string) => request<{ post: AdminPost; actions?: AuditLog[] }>(`/admin/posts/${encodeURIComponent(id)}`, token),
  removePost: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/posts/${encodeURIComponent(id)}/remove`, token, { method: 'POST', body: JSON.stringify(body) }),
  restorePost: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/posts/${encodeURIComponent(id)}/restore`, token, { method: 'POST', body: JSON.stringify(body) }),
  markPostSafe: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/posts/${encodeURIComponent(id)}/mark-safe`, token, { method: 'POST', body: JSON.stringify(body) }),
  removeFromDiscover: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/posts/${encodeURIComponent(id)}/remove-from-discover`, token, { method: 'POST', body: JSON.stringify(body) }),
  changePostCategory: (token: string, id: string, body: Record<string, unknown>) =>
    request<{ post: AdminPost }>(`/admin/posts/${encodeURIComponent(id)}/category`, token, { method: 'POST', body: JSON.stringify(body) }),
  comments: (token: string, query = '') => request<Paginated<AdminComment>>(`/admin/comments${query}`, token),
  removeComment: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/comments/${encodeURIComponent(id)}/remove`, token, { method: 'POST', body: JSON.stringify(body) }),
  restoreComment: (token: string, id: string, body: Record<string, unknown>) =>
    request(`/admin/comments/${encodeURIComponent(id)}/restore`, token, { method: 'POST', body: JSON.stringify(body) }),
  reportedMessages: (token: string, query = '') => request<Paginated<ReportSummary>>(`/admin/messages/reported${query}`, token),
  reportedMessage: (token: string, id: string) => request<ReportedMessageDetail>(`/admin/messages/reported/${encodeURIComponent(id)}`, token),
  reportedMessageAction: (token: string, id: string, body: Record<string, unknown>) =>
    request<{ report: ReportDetail }>(`/admin/messages/reported/${encodeURIComponent(id)}/action`, token, {
      method: 'POST',
      body: JSON.stringify(body),
    }),
  auditLogs: (token: string, query = '') => request<Paginated<AuditLog>>(`/admin/audit-logs${query}`, token),
};
