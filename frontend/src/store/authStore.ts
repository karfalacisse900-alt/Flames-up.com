import { create } from 'zustand';
import AsyncStorage from '@react-native-async-storage/async-storage';
import api from '../api/client';

interface User {
  id: string;
  email: string;
  username: string;
  full_name: string;
  bio?: string;
  profile_image?: string;
  location?: string;
  followers_count: number;
  following_count: number;
  posts_count: number;
  is_verified: boolean;
  is_admin?: boolean;
  is_publisher?: boolean;
}

interface AuthState {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  login: (email: string, password: string) => Promise<void>;
  register: (email: string, password: string, username: string, fullName: string) => Promise<void>;
  logout: () => Promise<void>;
  loadUser: () => Promise<void>;
  setUser: (user: any) => void;
  updateProfile: (data: Partial<User>) => Promise<void>;
}

export const useAuthStore = create<AuthState>((set, get) => ({
  user: null,
  token: null,
  isLoading: true,
  isAuthenticated: false,

  login: async (email: string, password: string) => {
    const response = await api.post('/auth/login', { email, password });
    const token = response.data.access_token || response.data.token;
    const rawUser = response.data.user;
    // Normalize boolean fields from D1 (integers) to JS booleans
    const user = {
      ...rawUser,
      is_verified: !!rawUser.is_verified,
      is_admin: !!rawUser.is_admin,
      is_publisher: !!rawUser.is_publisher,
    };
    await AsyncStorage.setItem('auth_token', token);
    await AsyncStorage.setItem('user', JSON.stringify(user));
    set({ user, token, isAuthenticated: true });
  },

  register: async (email: string, password: string, username: string, fullName: string) => {
    const response = await api.post('/auth/register', {
      email,
      password,
      username,
      full_name: fullName,
    });
    const token = response.data.access_token || response.data.token;
    const rawUser = response.data.user;
    const user = {
      ...rawUser,
      is_verified: !!rawUser.is_verified,
      is_admin: !!rawUser.is_admin,
      is_publisher: !!rawUser.is_publisher,
    };
    await AsyncStorage.setItem('auth_token', token);
    await AsyncStorage.setItem('user', JSON.stringify(user));
    set({ user, token, isAuthenticated: true });
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
          const rawUser = response.data;
          const user = {
            ...rawUser,
            is_verified: !!rawUser.is_verified,
            is_admin: !!rawUser.is_admin,
            is_publisher: !!rawUser.is_publisher,
          };
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
    const user = {
      ...userData,
      is_verified: !!userData.is_verified,
      is_admin: !!userData.is_admin,
      is_publisher: !!userData.is_publisher,
    };
    AsyncStorage.setItem('user', JSON.stringify(user));
    set({ user });
  },
}));
