// Theme matching Flames-Up original design
export const colors = {
  // Premium organic palette
  bgApp: '#F5F2EC',
  bgCard: '#FDFCF9',
  bgNav: 'rgba(253,252,249,0.92)',
  bgSubtle: '#EDEBE4',
  bgModal: '#FDFCF9',

  textPrimary: '#181C17',
  textSecondary: '#47594A',
  textHint: '#8C9E88',

  borderLight: '#DDD8CC',
  borderMedium: '#C5BAA4',
  borderSubtle: '#ECEAE3',

  accentPrimary: '#263F2A',
  accentPrimaryHover: '#182B1C',
  accentPrimaryLight: '#E0EDE2',
  accentSecondary: '#5A9478',
  accentSecondaryHover: '#3D7A5C',

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
  background: '#F5F2EC',
  primary: '#263F2A',
  primaryLight: '#E0EDE2',
  primaryDark: '#182B1C',
  textInverse: '#FFFFFF',
  textTertiary: '#8C9E88',
  backgroundSecondary: '#EDEBE4',
  border: '#DDD8CC',
  white: '#FFFFFF',
};

export const spacing = {
  xs: 4,
  sm: 8,
  md: 16,
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
  full: 9999,
};

export const typography = {
  h1: {
    fontSize: 28,
    fontWeight: '700' as const,
    fontStyle: 'italic' as const,
    lineHeight: 34,
  },
  h2: {
    fontSize: 22,
    fontWeight: '700' as const,
    lineHeight: 28,
  },
  h3: {
    fontSize: 18,
    fontWeight: '600' as const,
    lineHeight: 24,
  },
  body: {
    fontSize: 15,
    fontWeight: '400' as const,
    lineHeight: 22,
  },
  bodySmall: {
    fontSize: 13,
    fontWeight: '400' as const,
    lineHeight: 18,
  },
  caption: {
    fontSize: 11,
    fontWeight: '500' as const,
    lineHeight: 14,
    letterSpacing: 0.5,
  },
};

export const shadows = {
  elevation1: {
    shadowColor: 'rgba(28, 43, 26, 0.06)',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 1,
    shadowRadius: 6,
    elevation: 2,
  },
  elevation2: {
    shadowColor: 'rgba(28, 43, 26, 0.08)',
    shadowOffset: { width: 0, height: 8 },
    shadowOpacity: 1,
    shadowRadius: 24,
    elevation: 4,
  },
  elevation3: {
    shadowColor: 'rgba(28, 43, 26, 0.10)',
    shadowOffset: { width: 0, height: 16 },
    shadowOpacity: 1,
    shadowRadius: 40,
    elevation: 8,
  },
};
