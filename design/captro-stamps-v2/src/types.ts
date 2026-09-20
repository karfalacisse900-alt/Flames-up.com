/** Captro's taxonomy is fixed. Visual variants are not new stamp types. */
export type StampType = 'moment' | 'club' | 'event' | 'meetup' | 'deal';
export type StampVariant =
  | 'moment-paper' | 'moment-postal' | 'moment-voice'
  | 'club-oval' | 'club-member' | 'club-tag'
  | 'event-ticket' | 'event-screening' | 'event-postal'
  | 'meetup-note' | 'meetup-fold' | 'meetup-route'
  | 'deal-coupon' | 'deal-cashback' | 'deal-drop';
export type StampDensity = 'compact' | 'full';
export type StampState = 'active' | 'saved' | 'joined' | 'claimed' | 'used' | 'expired' | 'full';

/** Display model only. Prices, times, permissions and eligibility belong to your app. */
export interface StampData {
  id?: string;
  type: StampType;
  variant?: StampVariant;
  title: string;
  meta?: string;
  footer?: string;
  /** Short, app-authored summary for the feed. Full terms stay in the detail page. */
  compactText?: string;
  sideTop?: string;
  sideMain?: string;
  sideBottom?: string;
  state?: StampState;
  /** Normalized audio amplitudes from the recording, not a playback control. */
  waveform?: readonly number[];
}
export interface StampColors {
  paper: string;
  ink: string;
  line: string;
  accent: string;
}
export interface StampFonts { sans: string; serif: string; }
export interface RenderOptions {
  width?: number;
  density?: StampDensity;
  /** Color overrides must be six-digit hex values. */
  colors?: Partial<StampColors>;
  fonts?: Partial<StampFonts>;
  texture?: boolean;
  frameOnly?: boolean;
  /** React Native exposes accessibility on the wrapper instead of the SVG. */
  native?: boolean;
}
export interface StampField {
  key: 'label' | 'title' | 'meta' | 'footer' | 'compactText' | 'sideTop' | 'sideMain' | 'sideBottom';
  x: number;
  y: number;
  maxWidth: number;
  size: number;
  minSize: number;
  font: 'sans' | 'serif';
  weight: number;
  anchor: 'start' | 'middle' | 'end';
  tracking: number;
  overflow: 'ellipsis' | 'details' | 'offer';
  color: keyof StampColors;
  italic?: boolean;
}
export interface StampTemplate {
  id: StampVariant;
  type: StampType;
  label: string;
  colors: StampColors;
  full: StampLayout;
  compact: StampLayout;
}
export interface StampLayout {
  width: number;
  height: number;
  frame: string;
  fields: readonly StampField[];
}
