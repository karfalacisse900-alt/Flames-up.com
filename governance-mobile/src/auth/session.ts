import AsyncStorage from '@react-native-async-storage/async-storage';

const tokenKey = 'flames_governance_token';

export function getStoredToken() {
  return AsyncStorage.getItem(tokenKey);
}

export function saveStoredToken(token: string) {
  return AsyncStorage.setItem(tokenKey, token);
}

export function clearStoredToken() {
  return AsyncStorage.removeItem(tokenKey);
}
