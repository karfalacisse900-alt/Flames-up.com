import AsyncStorage from '@react-native-async-storage/async-storage';
import * as SecureStore from 'expo-secure-store';

const AUTH_TOKEN_KEY = 'auth_token';
const USER_KEY = 'user';
const INSTALL_ID_KEY = 'flames_client_install_id';

async function secureGet(key: string): Promise<string | null> {
  try {
    return await SecureStore.getItemAsync(key);
  } catch {
    return AsyncStorage.getItem(key);
  }
}

async function secureSet(key: string, value: string) {
  try {
    await SecureStore.setItemAsync(key, value);
  } catch {
    await AsyncStorage.setItem(key, value);
  }
}

async function secureDelete(key: string) {
  await SecureStore.deleteItemAsync(key).catch(() => undefined);
  await AsyncStorage.removeItem(key).catch(() => undefined);
}

function makeInstallId(): string {
  const randomUuid = globalThis.crypto?.randomUUID?.();
  if (randomUuid) return randomUuid;
  return `install_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 12)}`;
}

export async function getAuthToken() {
  return secureGet(AUTH_TOKEN_KEY);
}

export async function setAuthToken(token: string) {
  await secureSet(AUTH_TOKEN_KEY, token);
}

export async function setStoredUser(user: unknown) {
  await AsyncStorage.setItem(USER_KEY, JSON.stringify(user));
}

export async function getStoredUser() {
  return AsyncStorage.getItem(USER_KEY);
}

export async function removeSession() {
  await secureDelete(AUTH_TOKEN_KEY);
  await AsyncStorage.removeItem(USER_KEY).catch(() => undefined);
}

export async function getClientInstallId() {
  let id = await secureGet(INSTALL_ID_KEY);
  if (!id) {
    id = makeInstallId();
    await secureSet(INSTALL_ID_KEY, id);
  }
  return id;
}
