export type CreatorFilterAdjustments = {
  brightness?: number;
  contrast?: number;
  saturation?: number;
  warmth?: number;
  exposure?: number;
  fade?: number;
  grain?: number;
  vignette?: number;
  shadow?: number;
  highlight?: number;
};

export type CreatorFilterPreset = {
  id: string;
  name: string;
  tint: string;
  tintOpacity: number;
  fadeOpacity?: number;
  vignetteOpacity?: number;
  grainOpacity?: number;
  adjustments: CreatorFilterAdjustments;
};

export type CreatorFilterOverlay = {
  type: 'filter';
  id: 'filter';
  filterId: string;
  filterName: string;
  intensity: number;
  tint: string;
  tintOpacity: number;
  fadeOpacity?: number;
  vignetteOpacity?: number;
  grainOpacity?: number;
  adjustments: CreatorFilterAdjustments;
  mediaIndex?: number;
};

export type CreatorTextType = 'title' | 'subtitle' | 'label' | 'price' | 'rating' | 'note';
export type CreatorFontWeight = '400' | '500' | '600' | '700' | '800' | '900';

export type CreatorTextStylePreset = {
  id: string;
  name: string;
  textType: CreatorTextType;
  fontSize: number;
  fontWeight: CreatorFontWeight;
  color: string;
  background: string;
  borderColor?: string;
  shadow: boolean;
  radius: number;
  paddingX: number;
  paddingY: number;
  width: number;
};

export type CreatorTextOverlay = {
  type: 'text';
  id: string;
  textType: CreatorTextType;
  text: string;
  x: number;
  y: number;
  width: number;
  fontSize: number;
  fontFamily: string;
  fontWeight: CreatorFontWeight;
  color: string;
  background: string;
  borderColor?: string;
  opacity: number;
  shadow: boolean;
  radius: number;
  paddingX: number;
  paddingY: number;
  presetId: string;
  mediaIndex?: number;
};

export type CreatorEditorOverlay = CreatorFilterOverlay | CreatorTextOverlay;

export const CREATOR_FILTER_PRESETS: CreatorFilterPreset[] = [
  { id: 'fresh', name: 'Fresh', tint: '#E6FFF3', tintOpacity: 0.16, fadeOpacity: 0.04, adjustments: { brightness: 1.07, contrast: 1.02, saturation: 1.08, warmth: -0.04, exposure: 0.05 } },
  { id: 'soft_beige', name: 'Soft Beige', tint: '#EED9BC', tintOpacity: 0.22, fadeOpacity: 0.09, adjustments: { brightness: 1.05, contrast: 0.95, saturation: 0.9, warmth: 0.12, fade: 0.08 } },
  { id: 'cinematic', name: 'Cinematic', tint: '#2D4059', tintOpacity: 0.2, vignetteOpacity: 0.28, adjustments: { brightness: 0.96, contrast: 1.16, saturation: 0.96, warmth: -0.06, shadow: 0.14 } },
  { id: 'cafe_glow', name: 'Cafe Glow', tint: '#FFB45C', tintOpacity: 0.2, fadeOpacity: 0.04, adjustments: { brightness: 1.06, contrast: 1.02, saturation: 1.06, warmth: 0.18, highlight: 0.08 } },
  { id: 'urban_night', name: 'Urban Night', tint: '#0E1726', tintOpacity: 0.28, vignetteOpacity: 0.35, adjustments: { brightness: 0.9, contrast: 1.18, saturation: 0.9, warmth: -0.1, shadow: 0.22 } },
  { id: 'vintage_film', name: 'Vintage Film', tint: '#D7A66D', tintOpacity: 0.24, fadeOpacity: 0.13, grainOpacity: 0.18, adjustments: { brightness: 1.02, contrast: 0.94, saturation: 0.86, warmth: 0.16, grain: 0.2, fade: 0.14 } },
  { id: 'clean_bright', name: 'Clean Bright', tint: '#FFFFFF', tintOpacity: 0.14, fadeOpacity: 0.02, adjustments: { brightness: 1.12, contrast: 1.04, saturation: 1.02, exposure: 0.12, highlight: 0.1 } },
  { id: 'moody', name: 'Moody', tint: '#1F2933', tintOpacity: 0.24, vignetteOpacity: 0.26, adjustments: { brightness: 0.94, contrast: 1.12, saturation: 0.84, shadow: 0.18 } },
  { id: 'natural', name: 'Natural', tint: '#F8F2E8', tintOpacity: 0.06, adjustments: { brightness: 1.01, contrast: 1, saturation: 1, warmth: 0.03 } },
  { id: 'warm_lifestyle', name: 'Warm Lifestyle', tint: '#FFC27A', tintOpacity: 0.18, fadeOpacity: 0.05, adjustments: { brightness: 1.06, contrast: 1.03, saturation: 1.08, warmth: 0.2 } },
];

export const TEXT_STYLE_PRESETS: CreatorTextStylePreset[] = [
  { id: 'minimal_black', name: 'Minimal Black', textType: 'title', fontSize: 28, fontWeight: '500', color: '#111111', background: 'transparent', shadow: false, radius: 0, paddingX: 0, paddingY: 0, width: 0.72 },
  { id: 'soft_beige_card', name: 'Soft Beige Card', textType: 'note', fontSize: 18, fontWeight: '600', color: '#111111', background: '#F7F1E8', borderColor: '#E8DCCB', shadow: true, radius: 16, paddingX: 14, paddingY: 10, width: 0.7 },
  { id: 'white_glass_label', name: 'White Glass Label', textType: 'label', fontSize: 16, fontWeight: '600', color: '#111111', background: 'rgba(255,255,255,0.82)', borderColor: 'rgba(255,255,255,0.9)', shadow: true, radius: 18, paddingX: 12, paddingY: 8, width: 0.48 },
  { id: 'magazine_title', name: 'Magazine Title', textType: 'title', fontSize: 31, fontWeight: '500', color: '#FFFFFF', background: 'rgba(0,0,0,0.2)', shadow: true, radius: 8, paddingX: 10, paddingY: 6, width: 0.76 },
  { id: 'clean_price_tag', name: 'Clean Price Tag', textType: 'price', fontSize: 20, fontWeight: '500', color: '#111111', background: '#FFF93F', borderColor: '#111111', shadow: false, radius: 20, paddingX: 14, paddingY: 8, width: 0.38 },
  { id: 'small_creator_note', name: 'Small Creator Note', textType: 'note', fontSize: 14, fontWeight: '500', color: '#FFFFFF', background: 'rgba(17,17,17,0.58)', shadow: false, radius: 15, paddingX: 11, paddingY: 7, width: 0.5 },
  { id: 'rating_badge', name: 'Rating Badge', textType: 'rating', fontSize: 18, fontWeight: '500', color: '#111111', background: '#FFFFFF', borderColor: '#111111', shadow: true, radius: 18, paddingX: 12, paddingY: 8, width: 0.34 },
  { id: 'detail_card', name: 'Detail Card', textType: 'subtitle', fontSize: 17, fontWeight: '600', color: '#111111', background: '#FFFFFF', borderColor: '#EFE7DA', shadow: true, radius: 14, paddingX: 13, paddingY: 10, width: 0.66 },
];

export const TEXT_COLORS = ['#111111', '#FFFFFF', '#FFF93F', '#F7F1E8', '#E05C7A', '#6D5DFB'];

export function clampNumber(value: unknown, min: number, max: number, fallback: number) {
  const next = Number(value);
  if (!Number.isFinite(next)) return fallback;
  return Math.max(min, Math.min(max, next));
}

export function clampUnit(value: unknown, fallback = 0.5) {
  return clampNumber(value, 0.04, 0.96, fallback);
}

export function makeCreatorId(prefix: string) {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
}

export function filterOverlayFromPreset(preset: CreatorFilterPreset | null | undefined, intensity: number): CreatorFilterOverlay | null {
  if (!preset) return null;
  const safeIntensity = Math.round(clampNumber(intensity, 0, 100, 100));
  if (safeIntensity <= 0) return null;
  const multiplier = safeIntensity / 100;
  return {
    type: 'filter',
    id: 'filter',
    filterId: preset.id,
    filterName: preset.name,
    intensity: safeIntensity,
    tint: preset.tint,
    tintOpacity: Number((preset.tintOpacity * multiplier).toFixed(3)),
    fadeOpacity: Number(((preset.fadeOpacity || 0) * multiplier).toFixed(3)),
    vignetteOpacity: Number(((preset.vignetteOpacity || 0) * multiplier).toFixed(3)),
    grainOpacity: Number(((preset.grainOpacity || 0) * multiplier).toFixed(3)),
    adjustments: preset.adjustments,
    mediaIndex: 0,
  };
}

export function createTextOverlayFromPreset(preset: CreatorTextStylePreset, text?: string): CreatorTextOverlay {
  return {
    type: 'text',
    id: makeCreatorId('text'),
    textType: preset.textType,
    text: text || defaultTextForType(preset.textType),
    x: 0.5,
    y: 0.18,
    width: preset.width,
    fontSize: preset.fontSize,
    fontFamily: 'Inter',
    fontWeight: preset.fontWeight,
    color: preset.color,
    background: preset.background,
    borderColor: preset.borderColor,
    opacity: 1,
    shadow: preset.shadow,
    radius: preset.radius,
    paddingX: preset.paddingX,
    paddingY: preset.paddingY,
    presetId: preset.id,
    mediaIndex: 0,
  };
}

export function defaultTextForType(type: CreatorTextType) {
  if (type === 'price') return '$24';
  if (type === 'rating') return '4.8/5';
  if (type === 'label') return 'Favorite';
  if (type === 'subtitle') return 'Worth trying';
  if (type === 'note') return 'Creator note';
  return 'Add a title';
}

export function sanitizeTextOverlay(raw: any): CreatorTextOverlay | null {
  if (!raw || typeof raw !== 'object') return null;
  const text = String(raw.text || '').trim().slice(0, 140);
  if (!text) return null;
  const preset = TEXT_STYLE_PRESETS.find((item) => item.id === raw.presetId) || TEXT_STYLE_PRESETS[0];
  return {
    ...createTextOverlayFromPreset(preset, text),
    id: String(raw.id || makeCreatorId('text')).slice(0, 80),
    textType: (['title', 'subtitle', 'label', 'price', 'rating', 'note'].includes(raw.textType) ? raw.textType : preset.textType) as CreatorTextType,
    x: clampUnit(raw.x, 0.5),
    y: clampUnit(raw.y, 0.18),
    width: clampNumber(raw.width, 0.22, 0.9, preset.width),
    fontSize: Math.round(clampNumber(raw.fontSize, 12, 42, preset.fontSize)),
    fontFamily: String(raw.fontFamily || 'Inter').slice(0, 40),
    fontWeight: (['600', '700', '800', '900'].includes(String(raw.fontWeight)) ? String(raw.fontWeight) : preset.fontWeight) as CreatorTextOverlay['fontWeight'],
    color: String(raw.color || preset.color).slice(0, 32),
    background: String(raw.background ?? preset.background).slice(0, 48),
    borderColor: raw.borderColor ? String(raw.borderColor).slice(0, 48) : preset.borderColor,
    opacity: clampNumber(raw.opacity, 0.2, 1, 1),
    shadow: Boolean(raw.shadow),
    radius: clampNumber(raw.radius, 0, 26, preset.radius),
    paddingX: clampNumber(raw.paddingX, 0, 18, preset.paddingX),
    paddingY: clampNumber(raw.paddingY, 0, 14, preset.paddingY),
    mediaIndex: Math.max(0, Math.min(12, Number(raw.mediaIndex || raw.media_index || 0))),
  };
}

export function parseCreatorEditorOverlays(value: unknown) {
  const raw = Array.isArray(value) ? value : typeof value === 'string' && value.trim() ? safeParseArray(value) : [];
  const filter = raw.map((item: any) => item?.type === 'filter' ? item : null).filter(Boolean).slice(-1)[0];
  return {
    filterData: sanitizeFilterOverlay(filter),
    textOverlays: raw.map(sanitizeTextOverlay).filter(Boolean) as CreatorTextOverlay[],
  };
}

function safeParseArray(value: string) {
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function sanitizeFilterOverlay(raw: any): CreatorFilterOverlay | null {
  if (!raw || typeof raw !== 'object') return null;
  const preset = CREATOR_FILTER_PRESETS.find((item) => item.id === raw.filterId || item.name === raw.filterName);
  if (preset) return filterOverlayFromPreset(preset, raw.intensity || 100);
  const filterName = String(raw.filterName || '').trim().slice(0, 60);
  if (!filterName) return null;
  const intensity = Math.round(clampNumber(raw.intensity, 0, 100, 100));
  if (intensity <= 0) return null;
  return {
    type: 'filter',
    id: 'filter',
    filterId: String(raw.filterId || filterName).slice(0, 80),
    filterName,
    intensity,
    tint: String(raw.tint || '#FFFFFF').slice(0, 32),
    tintOpacity: clampNumber(raw.tintOpacity, 0, 0.6, 0.08),
    fadeOpacity: clampNumber(raw.fadeOpacity, 0, 0.4, 0),
    vignetteOpacity: clampNumber(raw.vignetteOpacity, 0, 0.6, 0),
    grainOpacity: clampNumber(raw.grainOpacity, 0, 0.4, 0),
    adjustments: raw.adjustments && typeof raw.adjustments === 'object' ? raw.adjustments : {},
    mediaIndex: Math.max(0, Math.min(12, Number(raw.mediaIndex || raw.media_index || 0))),
  };
}

export function buildCreatorEditorOverlays(filterData: CreatorFilterOverlay | null, textOverlays: CreatorTextOverlay[]): CreatorEditorOverlay[] {
  // This is the persisted editor data shape saved into posts.editor_overlays.
  return [
    filterData,
    ...textOverlays.map(sanitizeTextOverlay),
  ].filter(Boolean) as CreatorEditorOverlay[];
}
