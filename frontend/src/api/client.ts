import axios from 'axios';
import { getAuthToken, getClientInstallId, removeSession } from '../utils/sessionStorage';

const DEFAULT_API_URL = 'https://api.flames-up.com';

function normalizeApiURL(value?: string) {
  const raw = (value || DEFAULT_API_URL).trim().replace(/\/+$/, '');
  return raw.endsWith('/api') ? raw.slice(0, -4) : raw;
}

export const API_URL = normalizeApiURL(
  process.env.EXPO_PUBLIC_API_URL || process.env.EXPO_PUBLIC_BACKEND_URL
);

type SessionInvalidHandler = () => void | Promise<void>;
let sessionInvalidHandler: SessionInvalidHandler | null = null;
let cachedAuthToken: string | null = null;
let cachedAuthTokenExpiresAt = 0;
let cachedAuthTokenPromise: Promise<string | null> | null = null;
let cachedInstallId: string | null = null;
let cachedInstallIdPromise: Promise<string | null> | null = null;

const AUTH_TOKEN_CACHE_MS = 2500;

export function setSessionInvalidHandler(handler: SessionInvalidHandler | null) {
  sessionInvalidHandler = handler;
}

export function clearApiCredentialCache() {
  cachedAuthToken = null;
  cachedAuthTokenExpiresAt = 0;
  cachedAuthTokenPromise = null;
}

async function getCachedAuthToken() {
  const now = Date.now();
  if (cachedAuthTokenExpiresAt > now) return cachedAuthToken;
  if (!cachedAuthTokenPromise) {
    cachedAuthTokenPromise = getAuthToken()
      .then((token) => {
        cachedAuthToken = token;
        cachedAuthTokenExpiresAt = token ? Date.now() + AUTH_TOKEN_CACHE_MS : 0;
        return token;
      })
      .finally(() => {
        cachedAuthTokenPromise = null;
      });
  }
  return cachedAuthTokenPromise;
}

async function getCachedInstallId() {
  if (cachedInstallId) return cachedInstallId;
  if (!cachedInstallIdPromise) {
    cachedInstallIdPromise = getClientInstallId()
      .then((installId) => {
        cachedInstallId = installId;
        return installId;
      })
      .finally(() => {
        cachedInstallIdPromise = null;
      });
  }
  return cachedInstallIdPromise;
}

const api = axios.create({
  baseURL: `${API_URL}/api`,
  timeout: 30000,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor to add auth token
api.interceptors.request.use(
  async (config) => {
    const [token, installId] = await Promise.all([
      getCachedAuthToken(),
      getCachedInstallId(),
    ]);
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
    }
    if (installId) {
      config.headers['X-Client-Install-Id'] = installId;
    }
    return config;
  },
  (error) => Promise.reject(error)
);

// Response interceptor for error handling
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const status = error?.response?.status;
    const detail = error?.response?.data?.detail;
    const code = error?.response?.data?.code;

    if (status === 401 && (detail === 'Invalid token' || detail === 'Not authenticated' || code === 'INVALID_TOKEN' || code === 'USER_NOT_FOUND')) {
      clearApiCredentialCache();
      await removeSession();
      await sessionInvalidHandler?.();
    }

    return Promise.reject(error);
  }
);

export default api;
