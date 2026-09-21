import { TEMPLATES } from './templates';
import { METRICS } from './metrics';
import type { StampData, StampType, StampVariant, StampTemplate, StampField,
  RenderOptions, StampFonts, StampState, StampColors, StampDensity } from './types';

export const STAMP_VIEWBOX = { width: 640, height: 288 } as const;
export const DEFAULT_VARIANT: Record<StampType, StampVariant> = {
  moment: 'moment-paper', club: 'club-oval', event: 'event-ticket',
  meetup: 'meetup-note', deal: 'deal-coupon',
};
const STATE_LABELS: Record<StampState, string> = {
  active: '', saved: 'SAVED · VIEW DETAILS', joined: 'JOINED · VIEW DETAILS',
  claimed: 'CLAIMED · VIEW TERMS', used: 'USED · VIEW DETAILS',
  expired: 'EXPIRED · VIEW DETAILS', full: 'FULL · VIEW DETAILS',
};
const DEFAULT_FONTS: StampFonts = {
  sans: 'Inter, Arial, Helvetica, sans-serif',
  serif: 'EB Garamond, Georgia, Times New Roman, serif',
};

function text(value: unknown): string {
  if (value == null) return '';
  if (typeof value !== 'string') throw new TypeError('Stamp text fields must be strings.');
  if (value.length > 2000) throw new RangeError('Stamp text fields must be 2000 characters or fewer.');
  return value.replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/g, '')
    .replace(/\s+/g, ' ').trim();
}
/** Only text is accepted. User-supplied markup is never inserted into SVG. */
export function escapeXml(value: string): string {
  return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}
export function getTemplate(data: StampData): StampTemplate {
  if (!data || typeof data !== 'object') throw new TypeError('Stamp data is required.');
  if (!Object.prototype.hasOwnProperty.call(DEFAULT_VARIANT, data.type)) {
    throw new TypeError('Use only Moment, Club, Event, Meetup or Deal.');
  }
  const id = data.variant ?? DEFAULT_VARIANT[data.type];
  if (!Object.prototype.hasOwnProperty.call(TEMPLATES, id)) {
    throw new TypeError('Unknown stamp variant.');
  }
  const template = TEMPLATES[id];
  if (template.type !== data.type) throw new TypeError('Stamp variant must belong to its type.');
  if (data.state && !Object.prototype.hasOwnProperty.call(STATE_LABELS, data.state)) {
    throw new TypeError('Unknown stamp state.');
  }
  return template;
}

export function stampAccessibleLabel(data: StampData): string {
  const template = getTemplate(data);
  return [template.label, data.title, data.sideTop, data.sideMain, data.sideBottom,
    data.meta, data.footer, data.compactText, data.state && STATE_LABELS[data.state]].map(text).filter(Boolean).join('. ');
}
function estimatedWidth(value: string, field: StampField, size: number): number {
  const metrics = (METRICS[field.font + field.weight + (field.italic ? 'italic' : '')] ?? METRICS[field.font + (field.weight >= 600 ? '600' : '400')]);
  const chars = Array.from(value);
  const units = chars.reduce((sum, char) => sum + (metrics[char] ?? (char.charCodeAt(0) > 255 ? 1.05 : .65)), 0);
  return units * size * 1.035 + Math.max(0, chars.length - 1) * field.tracking;
}
function fit(value: string, field: StampField): { value: string; size: number } {
  let size = field.size;
  while (size > field.minSize && estimatedWidth(value, field, size) > field.maxWidth) size--;
  if (estimatedWidth(value, field, size) <= field.maxWidth) return { value, size };
  // Never display a truncated amount, minimum spend, date or payment condition.
  if (field.overflow !== 'ellipsis') {
    const fallback = field.overflow === 'offer' ? 'VIEW OFFER' : field.maxWidth < 160 ? 'INFO' : 'SEE DETAILS';
    let fallbackSize = Math.min(field.minSize, 34);
    while (fallbackSize > 20 && estimatedWidth(fallback, field, fallbackSize) > field.maxWidth) fallbackSize--;
    return { value: fallback, size: fallbackSize };
  }
  const chars = Array.from(value);
  while (chars.length > 0 && estimatedWidth(chars.join('') + '…', field, size) > field.maxWidth) chars.pop();
  return { value: chars.join('').trimEnd() + '…', size };
}
function fitLines(value: string, field: StampField): { lines: string[]; size: number } | null {
  const words = value.split(/\s+/).filter(Boolean);
  if (words.length < 2) return null;
  for (let size = field.size; size >= field.minSize; size--) {
    let best: { lines: string[]; imbalance: number } | null = null;
    for (let split = 1; split < words.length; split++) {
      const lines = [words.slice(0, split).join(' '), words.slice(split).join(' ')];
      const widths = lines.map(line => estimatedWidth(line, field, size));
      if (widths.some(width => width > field.maxWidth)) continue;
      const imbalance = Math.abs(widths[0] - widths[1]);
      if (!best || imbalance < best.imbalance) best = { lines, imbalance };
    }
    if (best) return { lines: best.lines, size };
  }
  return null;
}
function fieldValue(field: StampField, template: StampTemplate, data: StampData): string {
  if (field.key === 'label') return template.label;
  if (data.type === 'deal' && data.state && data.state !== 'active') {
    if (field.key === 'sideMain') return 'VIEW';
    if (field.key === 'sideBottom') return 'DETAILS';
  }
  // State belongs on the wrapper, never in place of price/qualifying terms.
  if (field.key === 'compactText') return text(data.compactText ?? data.footer ?? data.meta);
  return text(data[field.key]);
}
function waveMarkup(data: StampData, color: string, height: number): string {
  // Fixed line count keeps performance predictable. No invented data when audio is absent.
  if (!data.waveform?.length) return '';
  const values = data.waveform.slice(0, 40).map(n => typeof n === 'number' && Number.isFinite(n) ? Math.max(0, Math.abs(n)) : 0);
  const max = Math.max(...values, .00001);
  const dx = 402 / Math.max(1, values.length - 1);
  return '<g stroke="' + color + '" stroke-width="3.2" stroke-linecap="round">' + values.map((n, i) => {
    const h = 3 + (n / max) * 16;
    const x = 37 + i * dx;
    return `<path d="M${x.toFixed(2)} ${(height-50-h).toFixed(2)}v${(h*2).toFixed(2)}"/>`;
  }).join('') + '</g>';
}

/** Pure renderer, no network requests, external images, font files, masks or filters. */
export function renderStamp(data: StampData, options: RenderOptions = {}): string {
  const template = getTemplate(data);
  const width = options.width ?? 640;
  if (!Number.isFinite(width) || width <= 0) throw new RangeError('Stamp width must be a positive number.');
  if (!options.frameOnly && !text(data.title)) throw new TypeError('Stamp title is required.');
  const colors: StampColors = { ...template.colors, ...options.colors };
  for (const color of Object.values(colors)) {
    if (!/^#[0-9a-f]{6}$/i.test(color)) throw new TypeError('Stamp colors must be six-digit hex values.');
  }
  const fonts: StampFonts = { ...DEFAULT_FONTS, ...options.fonts };
  for (const font of Object.values(fonts)) {
    if (typeof font !== 'string' || font.length > 120 || /[<>\u0000-\u001f]/.test(font)) {
      throw new TypeError('Invalid font family.');
    }
  }
  const density = options.density ?? 'full';
  if (density !== 'full' && density !== 'compact') throw new TypeError('Stamp density must be full or compact.');
  const layout = template[density];
  let frame = layout.frame.replace(/\{\{(paper|ink|line|accent)\}\}/g, (_, key: keyof StampColors) => colors[key]);
  if (options.texture === false) frame = frame.replace(/<g data-texture="paper"[^>]*>[\s\S]*?<\/g>/g, '');
  let content = '';
  if (!options.frameOnly) {
    for (const field of layout.fields) {
      const raw = fieldValue(field, template, data);
      if (!raw) continue;
      const wrapped = field.key === 'title' && ['event', 'club', 'meetup'].includes(template.type)
        ? fitLines(raw, field) : null;
      if (wrapped && wrapped.lines.length > 1) {
        const lineHeight = wrapped.size * .92;
        const firstY = field.y - lineHeight * (wrapped.lines.length - 1) / 2;
        content += `<text x="${field.x}" y="${firstY}" font-family="${escapeXml(fonts[field.font])}" font-size="${wrapped.size}" font-weight="${field.weight}" font-style="${field.italic ? 'italic' : 'normal'}" letter-spacing="${field.tracking}" text-anchor="${field.anchor}" fill="${colors[field.color]}">`;
        content += wrapped.lines.map((line, index) => `<tspan x="${field.x}" dy="${index === 0 ? 0 : lineHeight}">${escapeXml(line)}</tspan>`).join('');
        content += '</text>';
        continue;
      }
      const fitted = fit(raw, field);
      content += `<text x="${field.x}" y="${field.y}" font-family="${escapeXml(fonts[field.font])}" font-size="${fitted.size}" font-weight="${field.weight}" font-style="${field.italic ? 'italic' : 'normal'}"${options.native ? '' : ' font-kerning="none"'} letter-spacing="${field.tracking}" text-anchor="${field.anchor}" fill="${colors[field.color]}"`;
      if (!options.native) content += ` data-field="${field.key}" data-max-width="${field.maxWidth}"`;
      content += '>' + escapeXml(fitted.value) + '</text>';
    }
    if (template.id === 'moment-voice') content += waveMarkup(data, colors.ink, layout.height);
  }
  if (options.native) frame = frame.replace(/ data-texture="paper"/g, '');
  const label = options.frameOnly ? template.label + ' frame' : stampAccessibleLabel(data);
  const accessibility = options.native ? '' : ` role="img" aria-label="${escapeXml(label)}"`;
  const title = options.native ? '' : '<title>' + escapeXml(label) + '</title>';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${width*layout.height/640}" viewBox="0 0 640 ${layout.height}"${accessibility}>${title}${frame}${content}</svg>`;
}
