import { appFontFamily } from './typography';

// Shared clean social-app palette. Keep surfaces bright and soft, with forest green for primary actions.
export const colors = {
  // Clean soft palette
  bgApp: '#FFFFFF',
  bgCard: '#FFFFFF',
  bgNav: '#FFFFFF',
  bgSubtle: '#FAFAF8',
  bgModal: '#FFFFFF',
  modalScrim: 'rgba(250,250,248,0.74)',
  surfaceSoft: '#FAFAF7',
  surfaceRaised: '#FFFFFF',
  surfaceTint: '#FBF8F2',
  lineSoft: '#EEF0EA',
  skeleton: '#F3F5F0',
  skeletonSoft: '#FAFAF8',
  emptyIconBg: '#F6F8F3',

  textPrimary: '#1D2119',
  textStrong: '#121510',
  textSecondary: '#687066',
  textHint: '#9EA59B',
  textDisabled: '#C7CCC4',

  borderLight: 'rgba(18,24,16,0.04)',
  borderMedium: '#E4E8E0',
  borderSubtle: 'rgba(18,24,16,0.055)',
  divider: 'rgba(18,24,16,0.06)',

  accentPrimary: '#20361F',
  accentPrimaryHover: '#172917',
  accentPrimaryLight: '#F0F6EE',
  accentSecondary: '#6B9D75',
  accentSecondaryHover: '#4D835B',
  accentLime: '#20361F',
  accentBlush: '#E9B7AE',

  // Fashion page colors
  fashionBg: '#F5F0E8',
  fashionCard: '#E8E2D8',
  fashionText: '#1C1A16',
  fashionHint: '#A09880',
  fashionBorder: '#BFB49C',

  // Flames logo colors
  flameDark: '#1C1A16',
  flameGold: '#D4A96A',

  // Status colors
  success: '#10B981',
  warning: '#F59E0B',
  error: '#E05C7A',
  info: '#1D9BF0',

  // Gradient colors
  gradientStart: '#6366f1',
  gradientEnd: '#8b5cf6',

  // Story ring
  storyRingStart: '#f09433',
  storyRingMid: '#dc2743',
  storyRingEnd: '#bc1888',

  // Avatar fallback
  avatarTeal: '#50C8A8',
  avatarPurple: '#6366f1',

  // Backward-compatible aliases
  background: '#FFFFFF',
  primary: '#20361F',
  accent: '#20361F',
  primaryLight: '#F0F6EE',
  primaryDark: '#172917',
  textInverse: '#FFFFFF',
  textTertiary: '#8A9385',
  backgroundSecondary: '#FAFAF8',
  border: '#EEF0EA',
  white: '#FFFFFF',
};

export const spacing = {
  xxs: 2,
  xs: 4,
  sm: 8,
  gutter: 12,
  md: 16,
  section: 20,
  lg: 24,
  xl: 32,
  xxl: 48,
};

export const borderRadius = {
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 28,
  organic: 18,
  card: 22,
  sheet: 28,
  full: 9999,
};

export const typography = {
  pageTitle: {
    fontFamily: appFontFamily,
    fontSize: 28,
    fontWeight: '700' as const,
    lineHeight: 34,
  },
  sectionTitle: {
    fontFamily: appFontFamily,
    fontSize: 20,
    fontWeight: '600' as const,
    lineHeight: 26,
  },
  h1: {
    fontFamily: appFontFamily,
    fontSize: 28,
    fontWeight: '700' as const,
    lineHeight: 34,
  },
  h2: {
    fontFamily: appFontFamily,
    fontSize: 24,
    fontWeight: '600' as const,
    lineHeight: 30,
  },
  h3: {
    fontFamily: appFontFamily,
    fontSize: 20,
    fontWeight: '600' as const,
    lineHeight: 26,
  },
  body: {
    fontFamily: appFontFamily,
    fontSize: 15,
    fontWeight: '400' as const,
    lineHeight: 22,
  },
  bodySmall: {
    fontFamily: appFontFamily,
    fontSize: 13,
    fontWeight: '400' as const,
    lineHeight: 18,
  },
  caption: {
    fontFamily: appFontFamily,
    fontSize: 11,
    fontWeight: '400' as const,
    lineHeight: 14,
    letterSpacing: 0,
  },
  button: {
    fontFamily: appFontFamily,
    fontSize: 15,
    fontWeight: '600' as const,
    lineHeight: 20,
  },
  label: {
    fontFamily: appFontFamily,
    fontSize: 12,
    fontWeight: '600' as const,
    lineHeight: 16,
    letterSpacing: 0,
  },
};

export const shadows = {
  elevation1: {
    shadowColor: '#20361F',
    shadowOffset: { width: 0, height: 5 },
    shadowOpacity: 0.08,
    shadowRadius: 18,
    elevation: 2,
  },
  elevation2: {
    shadowColor: '#20361F',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.105,
    shadowRadius: 32,
    elevation: 4,
  },
  elevation3: {
    shadowColor: '#20361F',
    shadowOffset: { width: 0, height: 16 },
    shadowOpacity: 0.13,
    shadowRadius: 42,
    elevation: 10,
  },
  sheet: {
    shadowColor: '#20361F',
    shadowOffset: { width: 0, height: -10 },
    shadowOpacity: 0.13,
    shadowRadius: 38,
    elevation: 12,
  },
  floating: {
    shadowColor: '#20361F',
    shadowOffset: { width: 0, height: 9 },
    shadowOpacity: 0.13,
    shadowRadius: 28,
    elevation: 8,
  },
};

export const layout = {
  screenMaxWidth: 620,
  pagePadding: 16,
  cardPadding: 16,
  sectionGap: 20,
  cardGap: 12,
  minTouchTarget: 44,
  iconButton: 40,
};

export const hitSlop = {
  top: 8,
  right: 8,
  bottom: 8,
  left: 8,
};

export const ui = {
  screen: {
    flex: 1,
    backgroundColor: colors.bgApp,
  },
  card: {
    backgroundColor: colors.bgCard,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    borderRadius: borderRadius.card,
  },
  raisedCard: {
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    borderRadius: borderRadius.card,
  },
  iconButton: {
    width: layout.iconButton,
    height: layout.iconButton,
    borderRadius: layout.iconButton / 2,
    alignItems: 'center' as const,
    justifyContent: 'center' as const,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
  },
  input: {
    minHeight: 48,
    borderRadius: 18,
    backgroundColor: colors.bgSubtle,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    paddingHorizontal: 14,
    color: colors.textPrimary,
    fontFamily: appFontFamily,
    fontSize: 15,
    lineHeight: 20,
    fontWeight: '400' as const,
  },
  primaryPill: {
    minHeight: 38,
    borderRadius: 19,
    backgroundColor: colors.accentPrimary,
    borderWidth: 1,
    borderColor: colors.accentPrimaryHover,
    alignItems: 'center' as const,
    justifyContent: 'center' as const,
    paddingHorizontal: 14,
  },
  secondaryPill: {
    minHeight: 44,
    borderRadius: 22,
    backgroundColor: colors.surfaceRaised,
    borderWidth: 1,
    borderColor: colors.borderSubtle,
    alignItems: 'center' as const,
    justifyContent: 'center' as const,
    paddingHorizontal: 16,
  },
};
