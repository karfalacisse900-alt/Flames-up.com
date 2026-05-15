import type { AdminUser, FilterStatus, GovernanceReport, GovernanceStats } from '@/types';

const configuredBaseUrl = process.env.EXPO_PUBLIC_API_URL || 'https://api.flames-up.com';
const baseUrl = configuredBaseUrl.replace(/\/+$/, '').replace(/\/api$/, '');

type LoginResponse = {
  access_token: string;
  token_type: string;
  user: AdminUser;
};

async function request<T>(path: string, token?: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set('Accept', 'application/json');

  if (init.body && !headers.has('Content-Type')) {
    headers.set('Content-Type', 'application/json');
  }

  if (token) {
    headers.set('Authorization', `Bearer ${token}`);
  }

  const response = await fetch(`${baseUrl}${path}`, {
    ...init,
    headers,
  });

  const text = await response.text();
  const payload = text ? JSON.parse(text) : null;

  if (!response.ok) {
    const message = payload?.detail || payload?.message || `Request failed with ${response.status}`;
    throw new Error(message);
  }

  return payload as T;
}

export function login(email: string, password: string) {
  return request<LoginResponse>('/api/auth/login', undefined, {
    method: 'POST',
    body: JSON.stringify({
      email: email.trim().toLowerCase(),
      password,
    }),
  });
}

export function getMe(token: string) {
  return request<AdminUser>('/api/admin/governance/me', token);
}

export function getStats(token: string) {
  return request<GovernanceStats>('/api/admin/governance/stats', token);
}

export function getReports(token: string, status: FilterStatus) {
  return request<GovernanceReport[]>(`/api/admin/governance/reports?status=${encodeURIComponent(status)}`, token);
}

export function resolveReport(token: string, reportId: string, adminNotes: string, actionTaken = 'resolved') {
  return request<{ resolved: boolean }>(`/api/admin/governance/reports/${reportId}/resolve`, token, {
    method: 'POST',
    body: JSON.stringify({
      admin_notes: adminNotes,
      action_taken: actionTaken,
    }),
  });
}

export function dismissReport(token: string, reportId: string, adminNotes: string) {
  return request<{ dismissed: boolean }>(`/api/admin/governance/reports/${reportId}/dismiss`, token, {
    method: 'POST',
    body: JSON.stringify({
      admin_notes: adminNotes,
    }),
  });
}

export function banUser(token: string, userId: string, reason: string) {
  return request<{ banned: boolean }>(`/api/admin/governance/users/${userId}/ban`, token, {
    method: 'POST',
    body: JSON.stringify({
      reason,
    }),
  });
}

export function unbanUser(token: string, userId: string) {
  return request<{ unbanned: boolean }>(`/api/admin/governance/users/${userId}/unban`, token, {
    method: 'POST',
    body: JSON.stringify({}),
  });
}

export function removePost(token: string, postId: string, reason: string, deleteStream = false) {
  return request<{ removed: boolean }>(`/api/admin/governance/posts/${postId}/remove`, token, {
    method: 'POST',
    body: JSON.stringify({
      reason,
      delete_stream: deleteStream,
    }),
  });
}
