import axios from 'axios';
import AsyncStorage from '@react-native-async-storage/async-storage';

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

export function setSessionInvalidHandler(handler: SessionInvalidHandler | null) {
  sessionInvalidHandler = handler;
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
    const token = await AsyncStorage.getItem('auth_token');
    if (token) {
      config.headers.Authorization = `Bearer ${token}`;
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
      await AsyncStorage.multiRemove(['auth_token', 'user']);
      await sessionInvalidHandler?.();
    }

    return Promise.reject(error);
  }
);

export default api;
