import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';
import api from '../api/client';

interface User {
  id: string;
  email: string;
  phone?: string;
  phone_verified?: boolean;
  username: string;
  full_name: string;
  bio: string;
  profile_image: string;
  location: string;
  city: string;
  age: string;
  looking_for: string;
  interests: string;
  social_website: string;
  social_tiktok: string;
  social_instagram: string;
  followers_count: number;
  following_count: number;
  posts_count: number;
  is_verified: boolean;
  is_admin?: boolean;
  is_publisher?: boolean;
  is_private?: boolean;
}

interface AuthState {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  login: (email: string, password: string) => Promise<void>;
  loginWithOAuth: (provider: 'google' | 'apple', idToken: string, extras?: Record<string, unknown>) => Promise<void>;
  startPhoneLogin: (phone: string) => Promise<{ detail: string; delivery?: string; dev_code?: string }>;
  verifyPhoneLogin: (phone: string, code: string, fullName?: string) => Promise<void>;
  register: (email: string, password: string, username: string, fullName: string) => Promise<void>;
  logout: () => Promise<void>;
  loadUser: () => Promise<void>;
  setUser: (user: any) => void;
  updateProfile: (data: Partial<User>) => Promise<void>;
}

function normalizeUser(rawUser: any): User {
  return {
    ...rawUser,
    bio: rawUser.bio || '',
    profile_image: rawUser.profile_image || '',
    location: rawUser.location || '',
    city: rawUser.city || '',
    age: rawUser.age ? String(rawUser.age) : '',
    looking_for: typeof rawUser.looking_for === 'string' ? rawUser.looking_for : JSON.stringify(rawUser.looking_for || []),
    interests: typeof rawUser.interests === 'string' ? rawUser.interests : JSON.stringify(rawUser.interests || []),
    social_website: rawUser.social_website || '',
    social_tiktok: rawUser.social_tiktok || '',
    social_instagram: rawUser.social_instagram || '',
    is_verified: !!rawUser.is_verified,
    is_admin: !!rawUser.is_admin,
    is_publisher: !!rawUser.is_publisher,
    is_private: !!rawUser.is_private,
    phone_verified: !!rawUser.phone_verified,
  };
}

async function persistSession(set: (state: Partial<AuthState>) => void, responseData: any) {
  const token = responseData.access_token || responseData.token;
  const user = normalizeUser(responseData.user);
  await AsyncStorage.setItem('auth_token', token);
  await AsyncStorage.setItem('user', JSON.stringify(user));
  set({ user, token, isAuthenticated: true });
}

export const useAuthStore = create<AuthState>((set, get) => ({
  user: null,
  token: null,
  isLoading: true,
  isAuthenticated: false,

  login: async (email: string, password: string) => {
    const response = await api.post('/auth/login', { email, password });
    await persistSession(set, response.data);
  },

  loginWithOAuth: async (provider: 'google' | 'apple', idToken: string, extras = {}) => {
    const response = await api.post(`/auth/oauth/${provider}`, { id_token: idToken, ...extras });
    await persistSession(set, response.data);
  },

  startPhoneLogin: async (phone: string) => {
    const response = await api.post('/auth/phone/start', { phone });
    return response.data;
  },

  verifyPhoneLogin: async (phone: string, code: string, fullName?: string) => {
    const response = await api.post('/auth/phone/verify', { phone, code, full_name: fullName });
    await persistSession(set, response.data);
  },

  register: async (email: string, password: string, username: string, fullName: string) => {
    const response = await api.post('/auth/register', {
      email,
      password,
      username,
      full_name: fullName,
    });
    await persistSession(set, response.data);
  },

  logout: async () => {
    await AsyncStorage.removeItem('auth_token');
    await AsyncStorage.removeItem('user');
    set({ user: null, token: null, isAuthenticated: false });
  },

  loadUser: async () => {
    try {
      const token = await AsyncStorage.getItem('auth_token');
      const userStr = await AsyncStorage.getItem('user');
      
      if (token && userStr) {
        // Verify token is still valid
        try {
          const response = await api.get('/auth/me');
          const user = normalizeUser(response.data);
          set({ user, token, isAuthenticated: true, isLoading: false });
        } catch {
          await AsyncStorage.removeItem('auth_token');
          await AsyncStorage.removeItem('user');
          set({ user: null, token: null, isAuthenticated: false, isLoading: false });
        }
      } else {
        set({ isLoading: false });
      }
    } catch {
      set({ isLoading: false });
    }
  },

  updateProfile: async (data: Partial<User>) => {
    const response = await api.put('/users/me', data);
    const updatedUser = response.data;
    await AsyncStorage.setItem('user', JSON.stringify(updatedUser));
    set({ user: updatedUser });
  },

  setUser: (userData: any) => {
    const user = normalizeUser(userData);
    AsyncStorage.setItem('user', JSON.stringify(user));
    set({ user });
  },
}));
