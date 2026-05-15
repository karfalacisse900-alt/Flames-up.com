import { create } from 'zustand';
import api, { setSessionInvalidHandler } from '../api/client';
import { isSupabaseConfigured, supabase } from '../api/supabase';
import { startSupabaseOAuth } from '../api/supabaseOAuth';
import { upsertSupabaseProfile } from '../api/supabaseData';
import { getAuthToken, getStoredUser, removeSession, setAuthToken, setStoredUser } from '../utils/sessionStorage';

type AppLanguage = 'en' | 'fr' | 'es';

function normalizeStoredLanguage(value?: string | null): AppLanguage {
  return value === 'fr' || value === 'es' ? value : 'en';
}

interface User {
  id: string;
  email: string;
  phone?: string;
  phone_verified?: boolean;
  username: string;
  full_name: string;
  bio: string;
  profile_image: string;
  cover_image?: string;
  profile_background_image?: string;
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
  is_premium?: boolean;
  premium_status?: string;
  premium_plan?: string;
  premium_until?: string;
  language?: AppLanguage;
}

interface AuthState {
  user: User | null;
  token: string | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  login: (email: string, password: string) => Promise<void>;
  loginWithOAuth: (provider: 'google' | 'apple', idToken: string, extras?: Record<string, unknown>) => Promise<void>;
  loginWithOAuthProvider: (provider: 'google' | 'apple') => Promise<void>;
  finishSupabaseSession: (session: any, extras?: Record<string, unknown>) => Promise<void>;
  startPhoneLogin: (phone: string) => Promise<{ detail: string; delivery?: string; dev_code?: string }>;
  verifyPhoneLogin: (phone: string, code: string, fullName?: string) => Promise<void>;
  startPhoneVerification: (phone: string) => Promise<{ detail: string; delivery?: string; dev_code?: string }>;
  verifyPhoneVerification: (phone: string, code: string) => Promise<void>;
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
    cover_image: rawUser.cover_image || '',
    profile_background_image: rawUser.profile_background_image || rawUser.cover_image || '',
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
    is_premium: !!rawUser.is_premium,
    premium_status: rawUser.premium_status || '',
    premium_plan: rawUser.premium_plan || '',
    premium_until: rawUser.premium_until || '',
    language: normalizeStoredLanguage(rawUser.language),
    phone_verified: !!rawUser.phone_verified,
  };
}

async function persistSession(set: (state: Partial<AuthState>) => void, responseData: any) {
  const token = responseData.access_token || responseData.token;
  const user = normalizeUser(responseData.user);
  await setAuthToken(token);
  await setStoredUser(user);
  set({ user, token, isAuthenticated: true });
  await upsertSupabaseProfile(user).catch(() => undefined);
}

async function persistBackendSessionFromSupabase(
  set: (state: Partial<AuthState>) => void,
  session: any,
  extras: Record<string, unknown> = {}
) {
  const accessToken = session?.access_token;
  if (!accessToken) {
    throw new Error('Supabase did not return an active session. Check your email to confirm the account, then sign in.');
  }
  const response = await api.post('/auth/supabase', {
    access_token: accessToken,
    ...extras,
  });
  await persistSession(set, response.data);
}

async function persistBackendOAuthSession(
  set: (state: Partial<AuthState>) => void,
  provider: 'google' | 'apple',
  idToken: string,
  extras: Record<string, unknown> = {}
) {
  const response = await api.post(`/auth/oauth/${provider}`, { id_token: idToken, ...extras });
  await persistSession(set, response.data);
}

export const useAuthStore = create<AuthState>((set, get) => ({
  user: null,
  token: null,
  isLoading: true,
  isAuthenticated: false,

  login: async (email: string, password: string) => {
    if (isSupabaseConfigured()) {
      const { data, error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) throw error;
      await persistBackendSessionFromSupabase(set, data.session);
      return;
    }
    const response = await api.post('/auth/login', { email, password });
    await persistSession(set, response.data);
  },

  loginWithOAuth: async (provider: 'google' | 'apple', idToken: string, extras = {}) => {
    if (isSupabaseConfigured()) {
      try {
        const { data, error } = await supabase.auth.signInWithIdToken({
          provider,
          token: idToken,
        } as any);
        if (error) throw error;
        await persistBackendSessionFromSupabase(set, data.session, extras);
        return;
      } catch (error: any) {
        if (provider !== 'google' && provider !== 'apple') throw error;
        // Native Google/Apple already gives us a signed provider ID token.
        // If Supabase's provider config is not ready, keep login working by
        // verifying that token on our backend and creating/linking the app user.
        await persistBackendOAuthSession(set, provider, idToken, {
          ...extras,
          supabase_id_token_error: error?.message || `Supabase ${provider} ID token sign-in failed`,
        });
        return;
      }
    }
    await persistBackendOAuthSession(set, provider, idToken, extras);
  },

  loginWithOAuthProvider: async (provider: 'google' | 'apple') => {
    if (!isSupabaseConfigured()) {
      throw new Error('Supabase is not configured for OAuth.');
    }
    const session = await startSupabaseOAuth(provider);
    await persistBackendSessionFromSupabase(set, session, { oauth_provider: provider });
  },

  finishSupabaseSession: async (session: any, extras = {}) => {
    await persistBackendSessionFromSupabase(set, session, extras);
  },

  startPhoneLogin: async (phone: string) => {
    const response = await api.post('/auth/phone/start', { phone });
    return response.data;
  },

  verifyPhoneLogin: async (phone: string, code: string, fullName?: string) => {
    const response = await api.post('/auth/phone/verify', { phone, code, full_name: fullName });
    await persistSession(set, response.data);
  },

  startPhoneVerification: async (phone: string) => {
    const response = await api.post('/users/me/phone/start', { phone });
    return response.data;
  },

  verifyPhoneVerification: async (phone: string, code: string) => {
    const response = await api.post('/users/me/phone/verify', { phone, code });
    const user = normalizeUser(response.data);
    await setStoredUser(user);
    set({ user });
  },

  register: async (email: string, password: string, username: string, fullName: string) => {
    if (isSupabaseConfigured()) {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            username,
            full_name: fullName,
          },
        },
      });
      if (error) throw error;
      await persistBackendSessionFromSupabase(set, data.session, { username, full_name: fullName, email });
      return;
    }
    const response = await api.post('/auth/register', {
      email,
      password,
      username,
      full_name: fullName,
    });
    await persistSession(set, response.data);
  },

  logout: async () => {
    if (isSupabaseConfigured()) {
      await supabase.auth.signOut().catch(() => {});
    }
    await removeSession();
    set({ user: null, token: null, isAuthenticated: false });
  },

  loadUser: async () => {
    try {
      const token = await getAuthToken();
      const userStr = await getStoredUser();
      
      if (token && userStr) {
        const cachedUser = normalizeUser(JSON.parse(userStr));
        set({ user: cachedUser, token, isAuthenticated: true, isLoading: false });

        try {
          const response = await api.get('/auth/me');
          const user = normalizeUser(response.data);
          await setStoredUser(user);
          set({ user, token, isAuthenticated: true, isLoading: false });
        } catch (error: any) {
          const status = error?.response?.status;
          if (status === 401 || status === 403) {
            await removeSession();
            set({ user: null, token: null, isAuthenticated: false, isLoading: false });
          }
        }
      } else {
        if (isSupabaseConfigured()) {
          const { data } = await supabase.auth.getSession();
          if (data.session) {
            await persistBackendSessionFromSupabase(set, data.session);
            set({ isLoading: false });
            return;
          }
        }
        set({ isLoading: false });
      }
    } catch {
      set({ isLoading: false });
    }
  },

  updateProfile: async (data: Partial<User>) => {
    const response = await api.put('/users/me', data);
    const updatedUser = normalizeUser(response.data);
    await setStoredUser(updatedUser);
    set({ user: updatedUser });
    await upsertSupabaseProfile(updatedUser).catch(() => undefined);
  },

  setUser: (userData: any) => {
    const user = normalizeUser(userData);
    setStoredUser(user);
    set({ user });
  },
}));

setSessionInvalidHandler(() => {
  useAuthStore.setState({
    user: null,
    token: null,
    isAuthenticated: false,
    isLoading: false,
  });
});
