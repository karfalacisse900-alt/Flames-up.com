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
const DEFAULT_TIMEOUT_MS = 12000;

export const ADMIN_TOKEN_KEY = 'captro.admin.token';
export const ADMIN_REFRESH_TOKEN_KEY = 'captro.admin.refresh-token';

export const API_BASE = (import.meta.env.VITE_CAPTRO_API_BASE || DEFAULT_API_BASE).replace(/\/+$/, '');
const API_TIMEOUT_MS = Number(import.meta.env.VITE_CAPTRO_API_TIMEOUT_MS || DEFAULT_TIMEOUT_MS);

export class ApiError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.status = status;
  }
}

function requestId() {
  return globalThis.crypto?.randomUUID?.() || `captro-admin-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

async function fetchWithTimeout(url: string, options: RequestInit = {}) {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), API_TIMEOUT_MS);

  try {
    return await fetch(url, {
      ...options,
      credentials: 'omit',
      signal: controller.signal,
    });
  } catch (error) {
    if ((error as Error)?.name === 'AbortError') {
      throw new ApiError('Captro API took too long to respond. Please retry.', 408);
    }
    throw new ApiError('Could not reach Captro API. Check your connection and try again.', 0);
  } finally {
    window.clearTimeout(timeout);
  }
}

async function readPayload(response: Response) {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return { detail: response.ok ? undefined : 'Captro API returned an unexpected response.' };
  }
}

async function refreshAdminSession(refreshToken: string) {
  const response = await fetchWithTimeout(`${API_BASE}/auth/refresh`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Request-ID': requestId() },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  const payload = await readPayload(response);
  if (!response.ok) throw new ApiError(payload?.detail || 'Session refresh failed', response.status);
  return payload as { access_token: string; refresh_token?: string };
}

async function request<T>(path: string, token: string, options: RequestInit = {}): Promise<T> {
  const makeHeaders = (accessToken: string) => ({
    'Content-Type': 'application/json',
    Authorization: `Bearer ${accessToken}`,
    'X-Request-ID': requestId(),
    ...(options.headers || {}),
  });

  let response = await fetchWithTimeout(`${API_BASE}${path}`, {
    ...options,
    headers: makeHeaders(token),
  });

  if ((response.status === 401 || response.status === 403) && !path.endsWith('/auth/refresh')) {
    const refreshToken = sessionStorage.getItem(ADMIN_REFRESH_TOKEN_KEY) || '';
    if (refreshToken) {
      try {
        const refreshed = await refreshAdminSession(refreshToken);
        const nextAccessToken = refreshed.access_token || token;
        const nextRefreshToken = refreshed.refresh_token || refreshToken;
        sessionStorage.setItem(ADMIN_TOKEN_KEY, nextAccessToken);
        sessionStorage.setItem(ADMIN_REFRESH_TOKEN_KEY, nextRefreshToken);
        response = await fetchWithTimeout(`${API_BASE}${path}`, {
          ...options,
          headers: makeHeaders(nextAccessToken),
        });
      } catch {
        sessionStorage.removeItem(ADMIN_TOKEN_KEY);
        sessionStorage.removeItem(ADMIN_REFRESH_TOKEN_KEY);
      }
    }
  }

  const payload = await readPayload(response);
  if (!response.ok) {
    throw new ApiError(payload?.detail || 'Request failed', response.status);
  }
  return payload as T;
}

export async function login(email: string, password: string) {
  const response = await fetchWithTimeout(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Request-ID': requestId() },
    body: JSON.stringify({ email, password }),
  });
  const payload = await readPayload(response);
  if (!response.ok) throw new ApiError(payload?.detail || 'Login failed', response.status);
  return payload as { access_token: string; refresh_token?: string };
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
  clearPostLocation: (token: string, id: string, body: Record<string, unknown>) =>
    request<{ post: AdminPost }>(`/admin/posts/${encodeURIComponent(id)}/location/clear`, token, { method: 'POST', body: JSON.stringify(body) }),
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
