import React from 'react';
import { View, Text, StyleSheet, ScrollView, TouchableOpacity } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../src/utils/theme';

export default function AboutScreen() {
  const router = useRouter();

  return (
    <SafeAreaView style={s.container} edges={['top']}>
      <View style={s.header}>
        <TouchableOpacity style={s.backBtn} onPress={() => router.back()}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>About</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={s.content}>
        <View style={s.logoWrap}>
          <View style={s.logoCircle}>
            <Text style={s.logoEmoji}>🔥</Text>
          </View>
          <Text style={s.appName}>Flames-Up</Text>
          <Text style={s.version}>Version 1.0.0</Text>
        </View>

        <View style={s.card}>
          <Text style={s.heading}>About Flames-Up</Text>
          <Text style={s.body}>
            Flames-Up is a hyperlocal lifestyle and community platform built for real connection. It helps people discover places nearby, share what they're doing, and connect with others in their city through authentic posts and verified check-ins.
          </Text>
        </View>

        <View style={s.card}>
          <Text style={s.heading}>Our Mission</Text>
          <Text style={s.body}>
            Our mission is simple: make your city feel smaller, safer, and more social.
          </Text>
          <Text style={[s.body, { marginTop: 12 }]}>
            Flames-Up is designed to be minimalist, aesthetic, and community-first — not algorithm chaos.
          </Text>
        </View>

        <View style={s.card}>
          <View style={s.valueRow}>
            <View style={s.valueIcon}><Ionicons name="location" size={18} color={colors.accentPrimary} /></View>
            <View style={s.valueText}>
              <Text style={s.valueTitle}>Hyperlocal</Text>
              <Text style={s.valueDesc}>Discover what's happening around you</Text>
            </View>
          </View>
          <View style={s.valueRow}>
            <View style={s.valueIcon}><Ionicons name="checkmark-circle" size={18} color={colors.accentPrimary} /></View>
            <View style={s.valueText}>
              <Text style={s.valueTitle}>Authentic</Text>
              <Text style={s.valueDesc}>Verified check-ins, real people</Text>
            </View>
          </View>
          <View style={s.valueRow}>
            <View style={s.valueIcon}><Ionicons name="people" size={18} color={colors.accentPrimary} /></View>
            <View style={s.valueText}>
              <Text style={s.valueTitle}>Community-First</Text>
              <Text style={s.valueDesc}>No algorithm chaos, just real connection</Text>
            </View>
          </View>
        </View>

        <Text style={s.footer}>© 2025 Flames-Up. All rights reserved.</Text>
      </ScrollView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 16, paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
  backBtn: { width: 44, height: 44, justifyContent: 'center', alignItems: 'center' },
  headerTitle: { fontSize: 18, fontWeight: '700', color: colors.textPrimary, fontStyle: 'italic' },
  content: { padding: 20, paddingBottom: 60 },
  logoWrap: { alignItems: 'center', marginBottom: 28 },
  logoCircle: { width: 72, height: 72, borderRadius: 36, backgroundColor: colors.accentPrimaryLight, justifyContent: 'center', alignItems: 'center', marginBottom: 12 },
  logoEmoji: { fontSize: 32 },
  appName: { fontSize: 24, fontWeight: '800', color: colors.textPrimary, fontStyle: 'italic' },
  version: { fontSize: 13, color: colors.textHint, marginTop: 4 },
  card: { backgroundColor: colors.bgCard, borderRadius: 20, padding: 20, marginBottom: 16, borderWidth: 1, borderColor: colors.borderLight },
  heading: { fontSize: 17, fontWeight: '700', color: colors.textPrimary, marginBottom: 10 },
  body: { fontSize: 15, color: colors.textSecondary, lineHeight: 23 },
  valueRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 12, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle },
  valueIcon: { width: 36, height: 36, borderRadius: 12, backgroundColor: colors.accentPrimaryLight, justifyContent: 'center', alignItems: 'center', marginRight: 14 },
  valueText: { flex: 1 },
  valueTitle: { fontSize: 15, fontWeight: '600', color: colors.textPrimary },
  valueDesc: { fontSize: 13, color: colors.textHint, marginTop: 2 },
  footer: { textAlign: 'center', fontSize: 13, color: colors.textHint, marginTop: 20 },
});
