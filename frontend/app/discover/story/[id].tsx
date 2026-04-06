import React from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, Image, ScrollView, Dimensions, Share,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { ALL_STORIES_MAP } from '../../../src/data/editorialContent';

const { width: SW } = Dimensions.get('window');

export default function StoryDetailScreen() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const { id } = useLocalSearchParams<{ id: string }>();

  const story = ALL_STORIES_MAP[id || ''];

  if (!story) {
    return (
      <View style={s.errorWrap}>
        <Text style={s.errorText}>Story not found</Text>
        <TouchableOpacity onPress={() => router.back()} style={s.errorBtn}>
          <Text style={s.errorBtnText}>Go Back</Text>
        </TouchableOpacity>
      </View>
    );
  }

  const handleShare = async () => {
    try { await Share.share({ message: story.title + " \u2014 Read on Flames-Up" }); } catch {}
  };

  const paragraphs = story.body.split('\n\n').filter((p: string) => p.trim());

  return (
    <View style={s.container}>
      <ScrollView showsVerticalScrollIndicator={false} contentContainerStyle={{ paddingBottom: 60 }}>
        {/* Hero Image */}
        <View style={s.heroWrap}>
          <Image source={{ uri: story.image }} style={s.heroImage} />
          <View style={s.heroOverlay} />

          <View style={[s.navRow, { paddingTop: insets.top + 8 }]}>
            <TouchableOpacity style={s.navBtn} onPress={() => router.back()}>
              <Ionicons name="arrow-back" size={20} color="#FFF" />
            </TouchableOpacity>
            <TouchableOpacity style={s.navBtn} onPress={handleShare}>
              <Ionicons name="share-outline" size={18} color="#FFF" />
            </TouchableOpacity>
          </View>

          <View style={s.heroContent}>
            <View style={s.categoryBadge}>
              <Text style={s.categoryText}>{story.category.toUpperCase()}</Text>
            </View>
            <Text style={s.heroTitle}>{story.title}</Text>
            <Text style={s.heroSub}>{story.subtitle}</Text>
          </View>
        </View>

        {/* Meta */}
        <View style={s.metaBar}>
          <View style={s.authorWrap}>
            <View style={s.authorAvatar}>
              <Ionicons name="person" size={14} color="#999" />
            </View>
            <View>
              <Text style={s.authorName}>{story.author}</Text>
              <Text style={s.readTime}>{story.readTime}</Text>
            </View>
          </View>
          <View style={s.locWrap}>
            <Ionicons name="location" size={13} color="#DC2626" />
            <Text style={s.locText}>{story.location}</Text>
          </View>
        </View>

        {/* Body */}
        <View style={s.bodyWrap}>
          {paragraphs.map((p: string, i: number) => (
            <Text key={i} style={s.bodyParagraph}>{p}</Text>
          ))}
        </View>

        {/* Footer */}
        <View style={s.divider} />
        <View style={s.relatedSection}>
          <Text style={s.relatedTitle}>More to explore</Text>
          <TouchableOpacity style={s.relatedBtn} onPress={() => router.replace('/(tabs)/discover' as any)}>
            <Ionicons name="compass-outline" size={16} color="#1A1A1A" />
            <Text style={s.relatedBtnText}>Back to Discover</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#FAFAF8' },
  errorWrap: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#FAFAF8' },
  errorText: { fontSize: 16, color: '#999', marginBottom: 16 },
  errorBtn: { backgroundColor: '#1A1A1A', paddingHorizontal: 24, paddingVertical: 12, borderRadius: 20 },
  errorBtnText: { color: '#FFF', fontWeight: '700' },
  heroWrap: { width: SW, height: SW * 1.0, position: 'relative' },
  heroImage: { width: '100%', height: '100%', position: 'absolute' },
  heroOverlay: { position: 'absolute', width: '100%', height: '100%', backgroundColor: 'rgba(0,0,0,0.45)' },
  navRow: { position: 'absolute', top: 0, left: 0, right: 0, flexDirection: 'row', justifyContent: 'space-between', paddingHorizontal: 16 },
  navBtn: { width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.15)', justifyContent: 'center', alignItems: 'center' },
  heroContent: { position: 'absolute', bottom: 32, left: 24, right: 24 },
  categoryBadge: { alignSelf: 'flex-start', backgroundColor: 'rgba(255,255,255,0.15)', paddingHorizontal: 12, paddingVertical: 5, borderRadius: 10, marginBottom: 12 },
  categoryText: { fontSize: 10, fontWeight: '800', color: '#FFF', letterSpacing: 1.5 },
  heroTitle: { fontSize: 28, fontWeight: '800', color: '#FFF', lineHeight: 34, letterSpacing: -0.5, marginBottom: 8 },
  heroSub: { fontSize: 15, color: 'rgba(255,255,255,0.7)', lineHeight: 22 },
  metaBar: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: 24, paddingVertical: 18, borderBottomWidth: 1, borderBottomColor: '#F0EDE7' },
  authorWrap: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  authorAvatar: { width: 36, height: 36, borderRadius: 18, backgroundColor: '#F5F0EB', justifyContent: 'center', alignItems: 'center' },
  authorName: { fontSize: 14, fontWeight: '700', color: '#1A1A1A' },
  readTime: { fontSize: 12, color: '#AAA', marginTop: 1 },
  locWrap: { flexDirection: 'row', alignItems: 'center', gap: 4 },
  locText: { fontSize: 13, fontWeight: '600', color: '#888' },
  bodyWrap: { paddingHorizontal: 24, paddingTop: 24 },
  bodyParagraph: { fontSize: 17, color: '#2A2A2A', lineHeight: 28, letterSpacing: -0.1, marginBottom: 20, fontWeight: '400' },
  divider: { height: 1, backgroundColor: '#F0EDE7', marginHorizontal: 24, marginTop: 8, marginBottom: 24 },
  relatedSection: { paddingHorizontal: 24, alignItems: 'center' },
  relatedTitle: { fontSize: 16, fontWeight: '700', color: '#1A1A1A', marginBottom: 14 },
  relatedBtn: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: '#F5F0EB', paddingHorizontal: 24, paddingVertical: 14, borderRadius: 24 },
  relatedBtnText: { fontSize: 14, fontWeight: '700', color: '#1A1A1A' },
});
