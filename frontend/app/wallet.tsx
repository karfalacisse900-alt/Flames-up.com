import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View,
} from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { Ionicons } from '@expo/vector-icons';
import { router, useLocalSearchParams } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { createCoinCheckout, getWallet, type CoinPackage, type CoinTransaction, type WalletState } from '../src/api/wallet';
import { createPremiumCheckout, getPremiumStatus, type PremiumStatus } from '../src/api/premium';
import { useAuthStore } from '../src/store/authStore';
import { appFontFamily } from '../src/utils/typography';
import { openSafeUrl } from '../src/utils/safeLinking';
import SensitiveScreen from '../src/components/SensitiveScreen';
import { colors, shadows } from '../src/utils/theme';

const RETURN_BASE_URL = 'https://flames-up.com/wallet';
const INK = colors.textPrimary;
const PAPER = colors.surfaceRaised;
const APP_BG = colors.bgApp;
const LIME = colors.accentPrimaryLight;
const GOLD = '#FFD866';
const GOLD_DARK = '#D98818';
const MUTED = colors.textSecondary;
const ACTION = colors.accentPrimary;

const DEFAULT_COIN_PACKS: CoinPackage[] = [
  { id: 'coins_100', label: '100 coins', coins: 100, amount_cents: 99, price: '$0.99' },
  { id: 'coins_600', label: '600 coins', coins: 600, amount_cents: 499, price: '$4.99' },
  { id: 'coins_1300', label: '1,300 coins', coins: 1300, amount_cents: 999, price: '$9.99' },
  { id: 'coins_3000', label: '3,000 coins', coins: 3000, amount_cents: 1999, price: '$19.99' },
];

const PREMIUM_FEATURES = [
  'Anonymous Notes up to 5 times per day',
  'Custom profile background banner',
  'Background music playback',
  'Premium badge on your profile',
];

function formatCoins(value: number) {
  return Math.max(0, Number(value || 0)).toLocaleString('en-US');
}

function formatTransactionType(type: string) {
  switch (type) {
    case 'purchase':
      return 'Coin purchase';
    case 'spend':
      return 'Spent coins';
    case 'boost':
      return 'Post boost';
    case 'gift_sent':
      return 'Gift sent';
    case 'gift_received':
      return 'Gift received';
    case 'refund':
      return 'Refund';
    case 'bonus':
      return 'Bonus';
    case 'admin_adjustment':
      return 'Adjustment';
    default:
      return 'Wallet activity';
  }
}

function formatDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  return date.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function packageValueText(pack: CoinPackage) {
  const centsPerCoin = pack.coins > 0 ? pack.amount_cents / pack.coins : 0;
  if (centsPerCoin <= 0.7) return 'Best value';
  if (centsPerCoin <= 0.85) return 'Creator pack';
  if (pack.coins >= 600) return 'Popular';
  return 'Starter';
}

function CoinLogo({ size = 64 }: { size?: number }) {
  const faceSize = Math.round(size * 0.9);
  const sideOffset = Math.max(4, Math.round(size * 0.08));
  const inner = Math.round(faceSize * 0.68);

  return (
    <View style={[s.coinWrap, { width: size, height: size }]}>
      <View
        style={[
          s.coinSide,
          {
            width: faceSize,
            height: faceSize,
            borderRadius: faceSize / 2,
            left: sideOffset,
            top: sideOffset,
          },
        ]}
      />
      <LinearGradient
        colors={['#FFF2A7', GOLD, '#F5A825']}
        start={{ x: 0.14, y: 0.08 }}
        end={{ x: 0.88, y: 0.96 }}
        style={[
          s.coinFace,
          {
            width: faceSize,
            height: faceSize,
            borderRadius: faceSize / 2,
          },
        ]}
      >
        <View style={[s.coinShine, { borderRadius: faceSize / 2 }]} />
        <View style={[s.coinRing, { width: inner, height: inner, borderRadius: inner / 2 }]} />
        <Text style={[s.coinLetter, { fontSize: Math.round(faceSize * 0.42), lineHeight: Math.round(faceSize * 0.5) }]}>C</Text>
      </LinearGradient>
    </View>
  );
}

export default function WalletScreen() {
  const insets = useSafeAreaInsets();
  const params = useLocalSearchParams<{ checkout?: string; premium?: string }>();
  const [wallet, setWallet] = useState<WalletState | null>(null);
  const [premium, setPremium] = useState<PremiumStatus | null>(null);
  const [loading, setLoading] = useState(true);
  const [buyingId, setBuyingId] = useState<string | null>(null);
  const [customCoins, setCustomCoins] = useState('');

  const load = useCallback(async () => {
    const [walletData, premiumData] = await Promise.all([
      getWallet(),
      getPremiumStatus().catch(() => null),
    ]);
    setWallet(walletData);
    if (premiumData) {
      setPremium(premiumData);
      const auth = useAuthStore.getState();
      if (auth.user) {
        auth.setUser({
          ...auth.user,
          is_premium: premiumData.is_premium,
          premium_status: premiumData.status,
          premium_plan: premiumData.plan,
          premium_until: premiumData.premium_until || '',
        });
      }
    }
  }, []);

  useEffect(() => {
    load()
      .catch(() => Alert.alert('Wallet', 'Could not load your wallet.'))
      .finally(() => setLoading(false));
  }, [load]);

  useEffect(() => {
    if (params.checkout === 'success' || params.premium === 'success') {
      load().catch(() => null);
    }
  }, [load, params.checkout, params.premium]);

  const reloadWallet = useCallback(async () => {
    await load();
  }, [load]);

  const customCoinNumber = useMemo(
    () => Math.max(0, Number.parseInt(customCoins.replace(/\D/g, ''), 10) || 0),
    [customCoins]
  );
  const customPrice = customCoinNumber > 0 ? `$${(customCoinNumber / 100).toFixed(2)}` : '$0.00';
  const transactions = wallet?.transactions || [];
  const packages = wallet?.packages?.length ? wallet.packages : DEFAULT_COIN_PACKS;

  const openCheckout = useCallback(async (input: { package_id?: string; coins?: number }, id: string) => {
    try {
      setBuyingId(id);
      const session = await createCoinCheckout({
        ...input,
        success_url: `${RETURN_BASE_URL}?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${RETURN_BASE_URL}?checkout=cancelled`,
        client_request_id: `wallet_${Date.now()}_${Math.random().toString(36).slice(2)}`,
      });
      if (!session.url) throw new Error('Missing checkout URL');
      await openSafeUrl(session.url);
    } catch (error: any) {
      const detail = error?.response?.data?.detail || 'Could not open Stripe Checkout.';
      Alert.alert('Wallet', detail);
    } finally {
      setBuyingId(null);
    }
  }, []);

  const buyPackage = useCallback((pack: CoinPackage) => {
    openCheckout({ package_id: pack.id }, pack.id);
  }, [openCheckout]);

  const buyCustom = useCallback(() => {
    const minCoins = wallet?.custom_purchase?.min_coins || 100;
    const maxCoins = wallet?.custom_purchase?.max_coins || 50000;
    if (customCoinNumber < minCoins || customCoinNumber > maxCoins) {
      Alert.alert('Custom coins', `Enter between ${formatCoins(minCoins)} and ${formatCoins(maxCoins)} coins.`);
      return;
    }
    openCheckout({ coins: customCoinNumber }, 'custom');
  }, [customCoinNumber, openCheckout, wallet?.custom_purchase?.max_coins, wallet?.custom_purchase?.min_coins]);

  const buyPremium = useCallback(async () => {
    try {
      setBuyingId('premium');
      const session = await createPremiumCheckout({
        success_url: `${RETURN_BASE_URL}?premium=success&session_id={CHECKOUT_SESSION_ID}`,
        cancel_url: `${RETURN_BASE_URL}?premium=cancelled`,
        client_request_id: `premium_${Date.now()}_${Math.random().toString(36).slice(2)}`,
      });
      if (!session.url) throw new Error('Missing checkout URL');
      await openSafeUrl(session.url);
    } catch (error: any) {
      const detail = error?.response?.data?.detail || 'Could not open Premium checkout.';
      Alert.alert('Premium', detail);
    } finally {
      setBuyingId(null);
    }
  }, []);

  if (loading) {
    return (
      <SensitiveScreen label="Wallet">
        <View style={[s.root, { paddingTop: insets.top }]}>
          <View style={s.center}>
            <CoinLogo size={76} />
            <ActivityIndicator color={INK} style={{ marginTop: 18 }} />
          </View>
        </View>
      </SensitiveScreen>
    );
  }

  return (
    <SensitiveScreen label="Wallet">
    <View style={[s.root, { paddingTop: insets.top }]}>
      <View style={s.header}>
        <TouchableOpacity style={s.headerButton} onPress={() => router.back()} activeOpacity={0.82}>
          <Ionicons name="chevron-back" size={24} color={INK} />
        </TouchableOpacity>
        <Text style={s.headerTitle}>Wallet</Text>
        <TouchableOpacity style={s.headerButton} onPress={reloadWallet} activeOpacity={0.82}>
          <Ionicons name="refresh" size={19} color={INK} />
        </TouchableOpacity>
      </View>

      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        contentContainerStyle={[s.content, { paddingBottom: insets.bottom + 28 }]}
        showsVerticalScrollIndicator={false}
      >
        <LinearGradient
          colors={[PAPER, '#F7F2DC', LIME]}
          start={{ x: 0.05, y: 0.06 }}
          end={{ x: 0.96, y: 0.92 }}
          style={s.balanceCard}
        >
          <View style={s.balanceTop}>
            <CoinLogo size={82} />
            <View style={s.balanceBadge}>
              <View style={s.liveDot} />
              <Text style={s.balanceBadgeText}>Secure backend balance</Text>
            </View>
          </View>
          <View>
            <Text style={s.balanceLabel}>Coin balance</Text>
            <View style={s.balanceNumberRow}>
              <Text style={s.balanceNumber} selectable>{formatCoins(wallet?.balance || 0)}</Text>
              <Text style={s.balanceUnit}>coins</Text>
            </View>
          </View>
          <View style={s.balanceStats}>
            <View style={s.statPill}>
              <Text style={s.statValue}>{formatCoins(wallet?.lifetime_purchased || 0)}</Text>
              <Text style={s.statLabel}>Bought</Text>
            </View>
            <View style={s.statPill}>
              <Text style={s.statValue}>{formatCoins(wallet?.lifetime_spent || 0)}</Text>
              <Text style={s.statLabel}>Used</Text>
            </View>
          </View>
        </LinearGradient>

        {!wallet?.stripe_connected ? (
          <View style={s.notice}>
            <Ionicons name="card-outline" size={19} color={GOLD_DARK} />
            <Text style={s.noticeText}>Stripe needs to be connected before coin purchases can open.</Text>
          </View>
        ) : null}

        <View style={s.sectionHeader}>
          <Text style={s.sectionTitle}>Recharge coins</Text>
          <Text style={s.sectionMeta}>{packages.length} packs</Text>
        </View>

        <View style={s.packageGrid}>
          {packages.map((pack, index) => (
            <TouchableOpacity
              key={pack.id}
              style={[s.packageCard, index === packages.length - 1 && s.packageFeatured]}
              onPress={() => buyPackage(pack)}
              disabled={buyingId === pack.id}
              activeOpacity={0.88}
            >
              <CoinLogo size={52} />
              <View style={s.packageBody}>
                <Text style={s.packageCoins}>{formatCoins(pack.coins)}</Text>
                <Text style={s.packageTag}>{packageValueText(pack)}</Text>
              </View>
              <View style={s.packageFooter}>
                <Text style={s.packagePrice}>{pack.price}</Text>
                <View style={s.packageArrow}>
                  {buyingId === pack.id ? (
                    <ActivityIndicator size="small" color={INK} />
                  ) : (
                    <Ionicons name="arrow-forward" size={17} color={INK} />
                  )}
                </View>
              </View>
            </TouchableOpacity>
          ))}
        </View>

        <View style={s.customCard}>
          <View style={s.customHeader}>
            <View style={{ flex: 1 }}>
              <Text style={s.customTitle}>Custom amount</Text>
              <Text style={s.customHint}>Choose the exact coin amount you want.</Text>
            </View>
            <Text style={s.customPrice}>{customPrice}</Text>
          </View>
          <View style={s.customInputRow}>
            <CoinLogo size={38} />
            <TextInput
              value={customCoins}
              onChangeText={(value) => setCustomCoins(value.replace(/\D/g, '').slice(0, 5))}
              keyboardType="number-pad"
              placeholder="Enter coins"
              placeholderTextColor="#92938B"
              style={s.customInput}
            />
            <TouchableOpacity style={s.customButton} onPress={buyCustom} disabled={buyingId === 'custom'} activeOpacity={0.86}>
              {buyingId === 'custom' ? <ActivityIndicator size="small" color={PAPER} /> : <Text style={s.customButtonText}>Buy</Text>}
            </TouchableOpacity>
          </View>
        </View>

        <LinearGradient colors={[PAPER, '#F3F6E8']} style={s.premiumCard}>
          <View style={s.premiumHead}>
            <View style={s.premiumIcon}>
              <Ionicons name="diamond-outline" size={20} color={INK} />
            </View>
            <View style={s.premiumCopy}>
              <Text style={s.premiumTitle}>{premium?.is_premium ? 'Premium active' : 'Premium creator'}</Text>
              <Text style={s.premiumSubtitle}>{premium?.monthly_price || '$4.99/month'} for extra creator tools.</Text>
            </View>
            <TouchableOpacity
              style={[s.premiumButton, premium?.is_premium && s.premiumButtonOn]}
              onPress={buyPremium}
              disabled={premium?.is_premium || buyingId === 'premium'}
              activeOpacity={0.86}
            >
              {buyingId === 'premium' ? (
                <ActivityIndicator size="small" color={PAPER} />
              ) : (
                <Text style={s.premiumButtonText}>{premium?.is_premium ? 'Active' : 'Join'}</Text>
              )}
            </TouchableOpacity>
          </View>
          <View style={s.premiumFeatures}>
            {PREMIUM_FEATURES.map((feature) => (
              <View key={feature} style={s.featureRow}>
                <Ionicons name="checkmark" size={16} color={INK} />
                <Text style={s.featureText}>{feature}</Text>
              </View>
            ))}
          </View>
        </LinearGradient>

        <View style={s.sectionHeader}>
          <Text style={s.sectionTitle}>Activity</Text>
          <Text style={s.sectionMeta}>{transactions.length}</Text>
        </View>
        <View style={s.historyList}>
          {transactions.length === 0 ? (
            <View style={s.emptyHistory}>
              <CoinLogo size={56} />
              <Text style={s.emptyTitle}>No activity yet</Text>
              <Text style={s.emptyText}>Purchases, gifts, refunds, boosts, and bonuses will show here.</Text>
            </View>
          ) : (
            transactions.map((transaction) => (
              <TransactionRow key={transaction.id} transaction={transaction} />
            ))
          )}
        </View>
      </ScrollView>
    </View>
    </SensitiveScreen>
  );
}

function TransactionRow({ transaction }: { transaction: CoinTransaction }) {
  const positive = transaction.amount > 0;
  const neutral = transaction.amount === 0;
  const iconName = positive ? 'add' : neutral ? 'remove' : 'arrow-up';
  return (
    <View style={s.transactionRow}>
      <View style={[s.transactionIcon, positive ? s.transactionIconPositive : neutral ? s.transactionIconNeutral : s.transactionIconNegative]}>
        <Ionicons name={iconName} size={16} color={positive ? INK : PAPER} />
      </View>
      <View style={s.transactionBody}>
        <Text style={s.transactionTitle}>{formatTransactionType(transaction.type)}</Text>
        <Text style={s.transactionDate}>{formatDate(transaction.created_at)}</Text>
      </View>
      <View style={s.transactionAmountWrap}>
        <Text style={[s.transactionAmount, positive ? s.amountPositive : neutral ? s.amountNeutral : s.amountNegative]}>
          {positive ? '+' : ''}{formatCoins(transaction.amount)}
        </Text>
        <Text style={s.transactionBalance}>{formatCoins(transaction.balance_after)} left</Text>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: APP_BG },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  header: {
    width: '100%',
    maxWidth: 620,
    alignSelf: 'center',
    minHeight: 62,
    paddingHorizontal: 18,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerButton: {
    width: 44,
    height: 44,
    borderRadius: 22,
    backgroundColor: colors.surfaceRaised,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    ...shadows.elevation1,
  },
  headerTitle: {
    color: INK,
    fontFamily: appFontFamily,
    fontSize: 18,
    lineHeight: 24,
    fontWeight: '600',
  },
  content: { width: '100%', maxWidth: 620, alignSelf: 'center', paddingHorizontal: 18, gap: 14 },
  coinWrap: { position: 'relative' },
  coinSide: {
    position: 'absolute',
    backgroundColor: GOLD_DARK,
    shadowColor: '#6B3D00',
    shadowOpacity: 0.22,
    shadowRadius: 8,
    shadowOffset: { width: 0, height: 4 },
    elevation: 4,
  },
  coinFace: {
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1.4,
    borderColor: '#B97410',
    overflow: 'hidden',
  },
  coinShine: {
    position: 'absolute',
    top: 4,
    left: 8,
    right: 10,
    height: '38%',
    backgroundColor: 'rgba(255,255,255,0.38)',
  },
  coinRing: {
    position: 'absolute',
    borderWidth: 2,
    borderColor: 'rgba(255,255,255,0.55)',
  },
  coinLetter: {
    color: '#8A5100',
    fontFamily: appFontFamily,
    fontWeight: '700',
    textShadowColor: 'rgba(255,255,255,0.55)',
    textShadowOffset: { width: 0, height: 1 },
    textShadowRadius: 0,
  },
  balanceCard: {
    minHeight: 276,
    borderRadius: 30,
    padding: 22,
    borderWidth: 1.3,
    borderColor: '#D7E59A',
    justifyContent: 'space-between',
    shadowColor: '#A8C400',
    shadowOpacity: 0.16,
    shadowRadius: 18,
    shadowOffset: { width: 0, height: 10 },
    elevation: 5,
  },
  balanceTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  balanceBadge: {
    minHeight: 34,
    borderRadius: 17,
    backgroundColor: 'rgba(255,255,255,0.55)',
    borderWidth: 1.2,
    borderColor: 'rgba(17,17,17,0.16)',
    paddingHorizontal: 12,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 7,
  },
  liveDot: { width: 7, height: 7, borderRadius: 4, backgroundColor: '#5CCD00' },
  balanceBadgeText: { color: INK, fontFamily: appFontFamily, fontSize: 12, lineHeight: 15, fontWeight: '600' },
  balanceLabel: { color: '#55564F', fontFamily: appFontFamily, fontSize: 15, lineHeight: 20, fontWeight: '600' },
  balanceNumberRow: { flexDirection: 'row', alignItems: 'flex-end', gap: 8 },
  balanceNumber: { color: INK, fontFamily: appFontFamily, fontSize: 48, lineHeight: 54, fontWeight: '700', fontVariant: ['tabular-nums'] },
  balanceUnit: { color: '#4F5148', fontFamily: appFontFamily, fontSize: 15, lineHeight: 27, fontWeight: '600' },
  balanceStats: { flexDirection: 'row', gap: 10 },
  statPill: {
    flex: 1,
    minHeight: 56,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.62)',
    borderWidth: 1,
    borderColor: 'rgba(17,17,17,0.12)',
    paddingHorizontal: 13,
    justifyContent: 'center',
  },
  statValue: { color: INK, fontFamily: appFontFamily, fontSize: 16, lineHeight: 21, fontWeight: '700', fontVariant: ['tabular-nums'] },
  statLabel: { color: '#686A62', fontFamily: appFontFamily, fontSize: 11, lineHeight: 15, fontWeight: '600' },
  notice: {
    minHeight: 52,
    borderRadius: 18,
    backgroundColor: '#FFF3D6',
    borderWidth: 1,
    borderColor: '#F3D086',
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: 14,
  },
  noticeText: { flex: 1, color: '#6B4A08', fontFamily: appFontFamily, fontSize: 13, lineHeight: 18, fontWeight: '600' },
  sectionHeader: { marginTop: 6, flexDirection: 'row', alignItems: 'flex-end', justifyContent: 'space-between' },
  sectionTitle: { color: INK, fontFamily: appFontFamily, fontSize: 21, lineHeight: 27, fontWeight: '600' },
  sectionMeta: { color: MUTED, fontFamily: appFontFamily, fontSize: 13, lineHeight: 18, fontWeight: '600' },
  packageGrid: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 },
  packageCard: {
    width: '48.5%',
    minHeight: 162,
    borderRadius: 24,
    backgroundColor: PAPER,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: 14,
    justifyContent: 'space-between',
    ...shadows.elevation1,
  },
  packageFeatured: { borderColor: '#B8CBAE', backgroundColor: '#F3F6E8' },
  packageBody: { marginTop: 8 },
  packageCoins: { color: INK, fontFamily: appFontFamily, fontSize: 21, lineHeight: 27, fontWeight: '700' },
  packageTag: { color: MUTED, fontFamily: appFontFamily, fontSize: 12, lineHeight: 16, fontWeight: '600', marginTop: 1 },
  packageFooter: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: 8 },
  packagePrice: { color: INK, fontFamily: appFontFamily, fontSize: 18, lineHeight: 23, fontWeight: '700' },
  packageArrow: { width: 34, height: 34, borderRadius: 17, backgroundColor: LIME, alignItems: 'center', justifyContent: 'center', borderWidth: 1.2, borderColor: ACTION },
  customCard: {
    borderRadius: 24,
    backgroundColor: PAPER,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    padding: 16,
    gap: 14,
    ...shadows.elevation1,
  },
  customHeader: { flexDirection: 'row', alignItems: 'flex-start', justifyContent: 'space-between', gap: 12 },
  customTitle: { color: INK, fontFamily: appFontFamily, fontSize: 19, lineHeight: 24, fontWeight: '700' },
  customHint: { color: MUTED, fontFamily: appFontFamily, fontSize: 12, lineHeight: 16, fontWeight: '600', marginTop: 2 },
  customPrice: { color: INK, fontFamily: appFontFamily, fontSize: 20, lineHeight: 25, fontWeight: '700', fontVariant: ['tabular-nums'] },
  customInputRow: { height: 58, borderRadius: 19, backgroundColor: colors.bgSubtle, flexDirection: 'row', alignItems: 'center', paddingHorizontal: 10, gap: 10 },
  customInput: { flex: 1, minWidth: 0, color: INK, fontFamily: appFontFamily, fontSize: 17, lineHeight: 23, fontWeight: '500', paddingVertical: 8 },
  customButton: { minWidth: 58, height: 42, borderRadius: 21, backgroundColor: ACTION, alignItems: 'center', justifyContent: 'center', borderWidth: 1.2, borderColor: ACTION, paddingHorizontal: 13 },
  customButtonText: { color: PAPER, fontFamily: appFontFamily, fontSize: 14, lineHeight: 18, fontWeight: '600' },
  premiumCard: {
    borderRadius: 24,
    borderWidth: 1,
    borderColor: '#D7DFCC',
    padding: 16,
    gap: 14,
    backgroundColor: colors.surfaceRaised,
    ...shadows.elevation1,
  },
  premiumHead: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  premiumIcon: { width: 46, height: 46, borderRadius: 23, backgroundColor: LIME, borderWidth: 1.2, borderColor: ACTION, alignItems: 'center', justifyContent: 'center' },
  premiumCopy: { flex: 1, minWidth: 0 },
  premiumTitle: { color: INK, fontFamily: appFontFamily, fontSize: 18, lineHeight: 23, fontWeight: '700' },
  premiumSubtitle: { color: MUTED, fontFamily: appFontFamily, fontSize: 12, lineHeight: 17, fontWeight: '600', marginTop: 2 },
  premiumButton: { minWidth: 66, height: 38, borderRadius: 19, backgroundColor: ACTION, alignItems: 'center', justifyContent: 'center', paddingHorizontal: 14 },
  premiumButtonOn: { backgroundColor: '#E4E4DD' },
  premiumButtonText: { color: PAPER, fontFamily: appFontFamily, fontSize: 13, lineHeight: 17, fontWeight: '600' },
  premiumFeatures: { gap: 8 },
  featureRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  featureText: { flex: 1, color: '#363832', fontFamily: appFontFamily, fontSize: 13, lineHeight: 18, fontWeight: '600' },
  historyList: { borderRadius: 22, overflow: 'hidden', backgroundColor: PAPER, borderWidth: 1, borderColor: colors.borderSubtle, ...shadows.elevation1 },
  emptyHistory: { minHeight: 158, alignItems: 'center', justifyContent: 'center', padding: 20, gap: 9 },
  emptyTitle: { color: INK, fontFamily: appFontFamily, fontSize: 17, lineHeight: 22, fontWeight: '600' },
  emptyText: { color: MUTED, fontFamily: appFontFamily, fontSize: 13, lineHeight: 18, fontWeight: '600', textAlign: 'center' },
  transactionRow: {
    minHeight: 72,
    paddingHorizontal: 14,
    paddingVertical: 11,
    flexDirection: 'row',
    alignItems: 'center',
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.divider,
  },
  transactionIcon: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center', marginRight: 11 },
  transactionIconPositive: { backgroundColor: LIME },
  transactionIconNegative: { backgroundColor: '#FFE2E8' },
  transactionIconNeutral: { backgroundColor: '#E8E8E2' },
  transactionBody: { flex: 1, minWidth: 0 },
  transactionTitle: { color: INK, fontFamily: appFontFamily, fontSize: 14, lineHeight: 19, fontWeight: '600' },
  transactionDate: { color: MUTED, fontFamily: appFontFamily, fontSize: 12, lineHeight: 16, fontWeight: '600', marginTop: 2 },
  transactionAmountWrap: { alignItems: 'flex-end' },
  transactionAmount: { fontFamily: appFontFamily, fontSize: 16, lineHeight: 21, fontWeight: '700', fontVariant: ['tabular-nums'] },
  amountPositive: { color: '#3D8B00' },
  amountNegative: { color: '#D8475B' },
  amountNeutral: { color: MUTED },
  transactionBalance: { color: MUTED, fontFamily: appFontFamily, fontSize: 11, lineHeight: 15, fontWeight: '600', marginTop: 2 },
});
