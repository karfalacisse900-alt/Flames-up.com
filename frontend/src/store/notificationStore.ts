import { create } from 'zustand';
import api from '../api/client';

type NotificationState = {
  unreadCount: number;
  isRefreshing: boolean;
  lastLoadedAt: number | null;
  setUnreadCount: (count: number) => void;
  refreshUnreadCount: () => Promise<number>;
  markAllRead: () => Promise<void>;
  reset: () => void;
};

function safeCount(value: unknown) {
  return Math.max(0, Math.floor(Number(value) || 0));
}

export const useNotificationStore = create<NotificationState>((set, get) => ({
  unreadCount: 0,
  isRefreshing: false,
  lastLoadedAt: null,

  setUnreadCount: (count) => set({ unreadCount: safeCount(count), lastLoadedAt: Date.now() }),

  refreshUnreadCount: async () => {
    if (get().isRefreshing) return get().unreadCount;
    set({ isRefreshing: true });
    try {
      const response = await api.get('/notifications/unread-count');
      const unreadCount = safeCount(response.data?.count);
      set({ unreadCount, isRefreshing: false, lastLoadedAt: Date.now() });
      return unreadCount;
    } catch {
      set({ isRefreshing: false });
      return get().unreadCount;
    }
  },

  markAllRead: async () => {
    set({ unreadCount: 0, lastLoadedAt: Date.now() });
    try {
      await api.post('/notifications/mark-read');
    } catch {
      // Keep the UI calm; the next refresh will reconcile with the server.
    }
  },

  reset: () => set({ unreadCount: 0, isRefreshing: false, lastLoadedAt: null }),
}));
