import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ScrollView,
  TextInput,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { colors, shadows } from '../src/utils/theme';

export default function ApplyPublisherScreen() {
  const router = useRouter();
  const [name, setName] = React.useState('');
  const [bio, setBio] = React.useState('');

  return (
    <SafeAreaView style={styles.container}>
      <View style={styles.header}>
        <TouchableOpacity onPress={() => router.back()} style={styles.backBtn}>
          <Ionicons name="arrow-back" size={22} color={colors.textPrimary} />
        </TouchableOpacity>
        <Text style={styles.title}>Local Publisher</Text>
        <View style={{ width: 44 }} />
      </View>

      <ScrollView contentContainerStyle={{ padding: 16 }}>
        <View style={styles.iconCircle}>
          <Ionicons name="newspaper" size={36} color={colors.info} />
        </View>
        <Text style={styles.heading}>Apply to be a Local Publisher</Text>
        <Text style={styles.desc}>Share news, events and stories from your community. Local publishers get featured on Discover.</Text>

        <Text style={styles.label}>Publisher Name</Text>
        <TextInput style={styles.input} placeholder="Your publication name" placeholderTextColor={colors.textHint} value={name} onChangeText={setName} />

        <Text style={styles.label}>About</Text>
        <TextInput style={[styles.input, { height: 100, textAlignVertical: 'top' }]} placeholder="Tell us about what you'll publish..." placeholderTextColor={colors.textHint} value={bio} onChangeText={setBio} multiline />

        <TouchableOpacity style={styles.submitBtn} onPress={() => Alert.alert('Submitted!', 'Your application has been submitted for review.')}>
          <Text style={styles.submitText}>Submit Application</Text>
        </TouchableOpacity>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.bgApp },
  header: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    paddingHorizontal: 16, paddingVertical: 8, borderBottomWidth: 1, borderBottomColor: colors.borderSubtle,
  },
  backBtn: { width: 44, height: 44, borderRadius: 22, justifyContent: 'center', alignItems: 'center' },
  title: { fontSize: 18, fontWeight: '700', color: colors.textPrimary },
  iconCircle: {
    width: 80, height: 80, borderRadius: 40, backgroundColor: '#DBEAFE',
    justifyContent: 'center', alignItems: 'center', alignSelf: 'center', marginTop: 20, marginBottom: 16,
  },
  heading: { fontSize: 22, fontWeight: '800', color: colors.textPrimary, textAlign: 'center', fontStyle: 'italic' },
  desc: { fontSize: 14, color: colors.textHint, textAlign: 'center', lineHeight: 20, marginTop: 8, marginBottom: 32 },
  label: { fontSize: 14, fontWeight: '600', color: colors.textPrimary, marginBottom: 6, marginTop: 16 },
  input: {
    backgroundColor: colors.bgCard, borderRadius: 14, padding: 16, fontSize: 15,
    color: colors.textPrimary, borderWidth: 1, borderColor: colors.borderLight,
  },
  submitBtn: {
    backgroundColor: colors.accentPrimary, paddingVertical: 16, borderRadius: 20,
    alignItems: 'center', marginTop: 32,
  },
  submitText: { fontSize: 16, fontWeight: '700', color: '#FFFFFF' },
});
