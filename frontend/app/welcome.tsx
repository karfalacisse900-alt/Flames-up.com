import React, { useState } from 'react';
import {
  View, Text, StyleSheet, TouchableOpacity, TextInput, ScrollView,
  KeyboardAvoidingView, Platform, Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';

const { width: SW } = Dimensions.get('window');
const STEPS = 5;

const GENDERS = ['Female', 'Male', 'Non-binary', 'Prefer not to say'];
const CATEGORIES = [
  { id: 'places', label: 'Places', sub: 'Locations, restaurants...', icon: 'location' },
  { id: 'food', label: 'Food & Drink', sub: 'Cuisines, recipes...', icon: 'restaurant' },
  { id: 'fashion', label: 'Fashion', sub: 'Outfits, streetwear...', icon: 'shirt' },
  { id: 'music', label: 'Music', sub: 'Artists, songs...', icon: 'musical-notes' },
  { id: 'travel', label: 'Travel', sub: 'Trips, adventures...', icon: 'airplane' },
  { id: 'nightlife', label: 'Nightlife', sub: 'Bars, clubs, events...', icon: 'moon' },
  { id: 'fitness', label: 'Fitness', sub: 'Workouts, health...', icon: 'barbell' },
  { id: 'art', label: 'Art & Culture', sub: 'Museums, galleries...', icon: 'color-palette' },
];

export default function WelcomeScreen() {
  const router = useRouter();
  const [step, setStep] = useState(0);
  const [gender, setGender] = useState('');
  const [age, setAge] = useState('');
  const [selectedCats, setSelectedCats] = useState<string[]>([]);
  const [locationGranted, setLocationGranted] = useState(false);
  const [notifsGranted, setNotifsGranted] = useState(false);

  const progress = (step + 1) / STEPS;

  const next = () => { if (step < STEPS - 1) setStep(step + 1); else finish(); };
  const back = () => { if (step > 0) setStep(step - 1); };

  const requestLocation = async () => {
    try {
      const { status } = await Location.requestForegroundPermissionsAsync();
      setLocationGranted(status === 'granted');
    } catch {}
    next();
  };

  const requestNotifs = async () => {
    try {
      const { status } = await Notifications.requestPermissionsAsync();
      setNotifsGranted(status === 'granted');
    } catch {}
    next();
  };

  const toggleCat = (id: string) => {
    setSelectedCats(prev => prev.includes(id) ? prev.filter(c => c !== id) : [...prev, id]);
  };

  const finish = () => {
    router.replace('/(auth)/login' as any);
  };

  // Step 0: Gender
  const renderGender = () => (
    <View style={s.stepContainer}>
      <Text style={s.questionLight}>What is your gender?</Text>
      <Text style={s.subLight}>This helps us find you more relevant content.{'\n'}We won't show this on your profile.</Text>
      <View style={s.optionsList}>
        {GENDERS.map(g => (
          <TouchableOpacity key={g} style={[s.optionRow, gender === g && s.optionRowActive]} onPress={() => setGender(g)}>
            <Text style={[s.optionText, gender === g && s.optionTextActive]}>{g}</Text>
            <View style={[s.radio, gender === g && s.radioActive]}>
              {gender === g && <Ionicons name="checkmark" size={14} color="#FFF" />}
            </View>
          </TouchableOpacity>
        ))}
      </View>
      <View style={s.bottomArea}>
        <TouchableOpacity style={[s.continueBtn, !gender && s.continueBtnDisabled]} disabled={!gender} onPress={next}>
          <Text style={s.continueTx}>Continue</Text>
        </TouchableOpacity>
      </View>
    </View>
  );

  // Step 1: Age
  const renderAge = () => (
    <View style={s.stepContainer}>
      <Text style={s.questionLight}>How old are you?</Text>
      <View style={s.ageDisplay}>
        <TextInput
          style={s.ageInput}
          value={age}
          onChangeText={t => setAge(t.replace(/[^0-9]/g, '').slice(0, 2))}
          keyboardType="number-pad"
          maxLength={2}
          placeholder="18"
          placeholderTextColor="#DDD"
        />
      </View>
      <View style={s.bottomArea}>
        <TouchableOpacity style={[s.continueBtn, !age && s.continueBtnDisabled]} disabled={!age} onPress={next}>
          <Text style={s.continueTx}>Continue</Text>
        </TouchableOpacity>
      </View>
    </View>
  );

  // Step 2: Location
  const renderLocation = () => (
    <View style={[s.stepContainer, s.darkBg]}>
      <Text style={s.questionDark}>Turn your location on for suggestions in your area</Text>
      <View style={s.illustrationWrap}>
        <View style={s.globeIcon}><Ionicons name="globe" size={80} color="#666" /></View>
        <View style={s.pinFloat}><Ionicons name="location" size={40} color="#3B82F6" /></View>
      </View>
      <View style={s.bottomArea}>
        <TouchableOpacity style={s.continueBtnWhite} onPress={requestLocation}>
          <Text style={s.continueTxDark}>Continue</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={next}><Text style={s.skipTx}>Skip for now</Text></TouchableOpacity>
      </View>
    </View>
  );

  // Step 3: Notifications
  const renderNotifs = () => (
    <View style={[s.stepContainer, s.darkBg]}>
      <Text style={s.questionDark}>Allow notifications so you can stay informed</Text>
      <View style={s.illustrationWrap}>
        <View style={s.bellIcon}><Ionicons name="notifications" size={80} color="#3B82F6" /></View>
        <View style={s.chatFloat}><Ionicons name="chatbubble-ellipses" size={32} color="#999" /></View>
      </View>
      <View style={s.bottomArea}>
        <TouchableOpacity style={s.continueBtnWhite} onPress={requestNotifs}>
          <Text style={s.continueTxDark}>Continue</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={next}><Text style={s.skipTx}>Skip for now</Text></TouchableOpacity>
      </View>
    </View>
  );

  // Step 4: Categories
  const renderCategories = () => (
    <View style={s.stepContainer}>
      <Text style={s.questionLight}>What are you into?</Text>
      <Text style={s.subLight}>Choose categories to get started</Text>
      <ScrollView style={s.catScroll} showsVerticalScrollIndicator={false}>
        <View style={s.catGrid}>
          {CATEGORIES.map(cat => (
            <TouchableOpacity key={cat.id} style={[s.catCard, selectedCats.includes(cat.id) && s.catCardActive]} onPress={() => toggleCat(cat.id)}>
              <Ionicons name={cat.icon as any} size={32} color={selectedCats.includes(cat.id) ? '#1A1A1A' : '#AAA'} />
              <Text style={s.catLabel}>{cat.label}</Text>
              <Text style={s.catSub}>{cat.sub}</Text>
            </TouchableOpacity>
          ))}
        </View>
      </ScrollView>
      <View style={s.bottomArea}>
        <TouchableOpacity style={s.continueBtn} onPress={finish}>
          <Text style={s.continueTx}>Continue</Text>
        </TouchableOpacity>
        <TouchableOpacity onPress={finish}><Text style={s.skipTxLight}>Skip for now</Text></TouchableOpacity>
      </View>
    </View>
  );

  const isDark = step === 2 || step === 3;

  return (
    <SafeAreaView style={[s.safe, isDark && s.darkBg]}>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        {/* Progress bar + back */}
        <View style={s.topBar}>
          {step > 0 ? (
            <TouchableOpacity style={[s.backBtn, isDark && s.backBtnDark]} onPress={back}>
              <Ionicons name="chevron-back" size={20} color={isDark ? '#FFF' : '#1A1A1A'} />
            </TouchableOpacity>
          ) : <View style={{ width: 40 }} />}
          <View style={s.progressBar}>
            <View style={[s.progressFill, { width: `${progress * 100}%` }]} />
          </View>
        </View>

        {step === 0 && renderGender()}
        {step === 1 && renderAge()}
        {step === 2 && renderLocation()}
        {step === 3 && renderNotifs()}
        {step === 4 && renderCategories()}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const s = StyleSheet.create({
  safe: { flex: 1, backgroundColor: '#F5F2EE' },
  darkBg: { backgroundColor: '#1A1A1A' },

  topBar: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingVertical: 8, gap: 12 },
  backBtn: { width: 40, height: 40, borderRadius: 20, backgroundColor: '#FFF', justifyContent: 'center', alignItems: 'center' },
  backBtnDark: { backgroundColor: '#333' },
  progressBar: { flex: 1, height: 3, backgroundColor: '#E0DCD7', borderRadius: 2 },
  progressFill: { height: '100%', backgroundColor: '#1A1A1A', borderRadius: 2 },

  stepContainer: { flex: 1, paddingHorizontal: 24 },
  questionLight: { fontSize: 28, fontWeight: '900', color: '#1A1A1A', textAlign: 'center', marginTop: 40, letterSpacing: -0.5 },
  questionDark: { fontSize: 28, fontWeight: '900', color: '#FFF', textAlign: 'center', marginTop: 40, letterSpacing: -0.5 },
  subLight: { fontSize: 15, color: '#999', textAlign: 'center', marginTop: 8, lineHeight: 22 },

  optionsList: { marginTop: 40, gap: 10 },
  optionRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', backgroundColor: '#FFF', borderRadius: 16, paddingHorizontal: 24, paddingVertical: 18, borderWidth: 1.5, borderColor: '#F0EDE7' },
  optionRowActive: { backgroundColor: '#1A1A1A', borderColor: '#1A1A1A' },
  optionText: { fontSize: 17, fontWeight: '600', color: '#1A1A1A' },
  optionTextActive: { color: '#FFF' },
  radio: { width: 24, height: 24, borderRadius: 12, borderWidth: 2, borderColor: '#DDD', justifyContent: 'center', alignItems: 'center' },
  radioActive: { backgroundColor: '#1A1A1A', borderColor: '#1A1A1A' },

  ageDisplay: { alignItems: 'center', marginTop: 40 },
  ageInput: { fontSize: 72, fontWeight: '900', color: '#1A1A1A', textAlign: 'center', width: 200 },

  illustrationWrap: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  globeIcon: { opacity: 0.6 },
  pinFloat: { position: 'absolute', top: '30%' },
  bellIcon: {},
  chatFloat: { position: 'absolute', right: '25%', top: '25%' },

  catScroll: { flex: 1, marginTop: 20 },
  catGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  catCard: { width: (SW - 58) / 2, backgroundColor: '#FFF', borderRadius: 16, padding: 20, alignItems: 'center', gap: 8, borderWidth: 1.5, borderColor: '#F0EDE7' },
  catCardActive: { borderColor: '#1A1A1A', backgroundColor: '#F8F8F8' },
  catLabel: { fontSize: 15, fontWeight: '700', color: '#1A1A1A' },
  catSub: { fontSize: 12, color: '#999', textAlign: 'center' },

  bottomArea: { paddingBottom: 24, gap: 16, marginTop: 'auto' },
  continueBtn: { backgroundColor: '#1A1A1A', borderRadius: 16, paddingVertical: 18, alignItems: 'center' },
  continueBtnDisabled: { opacity: 0.3 },
  continueTx: { fontSize: 16, fontWeight: '700', color: '#FFF' },
  continueBtnWhite: { backgroundColor: '#FFF', borderRadius: 16, paddingVertical: 18, alignItems: 'center' },
  continueTxDark: { fontSize: 16, fontWeight: '700', color: '#1A1A1A' },
  skipTx: { fontSize: 14, fontWeight: '500', color: '#666', textAlign: 'center' },
  skipTxLight: { fontSize: 14, fontWeight: '500', color: '#999', textAlign: 'center' },
});
