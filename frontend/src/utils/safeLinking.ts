import { Alert, Linking } from 'react-native';
import { assessExternalUrl } from '../native/securityEngine';

export function normalizeSafeUrl(value?: string | null): string {
  const assessment = assessExternalUrl(value);
  return assessment.allowed ? assessment.safeUrl : '';
}

export async function openSafeUrl(value?: string | null) {
  const url = normalizeSafeUrl(value);
  if (!url) {
    Alert.alert('Invalid link', 'This link cannot be opened safely.');
    return;
  }
  await Linking.openURL(url);
}
