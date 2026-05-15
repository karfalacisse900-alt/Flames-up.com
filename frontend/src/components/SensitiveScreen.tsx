import React, { useEffect, useState } from 'react';
import { AppState, Platform, StyleProp, StyleSheet, Text, View, ViewStyle } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../utils/theme';

type SensitiveScreenProps = {
  children: React.ReactNode;
  label?: string;
  style?: StyleProp<ViewStyle>;
};

export default function SensitiveScreen({ children, label = 'Sensitive screen', style }: SensitiveScreenProps) {
  const [covered, setCovered] = useState(false);

  useEffect(() => {
    // Sensitive screens get a privacy cover when the app is backgrounded or hidden.
    // This does not claim to block screenshots; native secure-window support can be added in a dev build later.
    const subscription = AppState.addEventListener('change', (state) => {
      setCovered(state !== 'active');
    });

    if (Platform.OS === 'web' && typeof document !== 'undefined') {
      const updateWebPrivacy = () => setCovered(document.hidden);
      document.addEventListener('visibilitychange', updateWebPrivacy);
      return () => {
        subscription.remove();
        document.removeEventListener('visibilitychange', updateWebPrivacy);
      };
    }

    return () => subscription.remove();
  }, []);

  return (
    <View style={[styles.root, style]}>
      {children}
      {covered ? (
        <View style={styles.cover} pointerEvents="auto">
          <Ionicons name="shield-checkmark-outline" size={26} color="#111" />
          <Text style={styles.coverTitle}>{label}</Text>
          <Text style={styles.coverText}>Hidden while the app is not active.</Text>
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  cover: {
    ...StyleSheet.absoluteFillObject,
    zIndex: 9999,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 8,
    backgroundColor: colors.bgApp,
    paddingHorizontal: 32,
  },
  coverTitle: { fontSize: 18, fontWeight: '700', color: '#111', textAlign: 'center' },
  coverText: { fontSize: 13, color: '#6B7280', textAlign: 'center' },
});
