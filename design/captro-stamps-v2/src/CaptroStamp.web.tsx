import * as React from 'react';
import { renderStamp, stampAccessibleLabel } from './render-stamp';
import type { StampData, StampFonts, StampDensity } from './types';
import './stamp.css';

export interface CaptroStampProps {
  data: StampData;
  width?: number;
  density?: StampDensity;
  texture?: boolean;
  fonts?: Partial<StampFonts>;
  className?: string;
  onPress?: (data: StampData) => void;
}

/** One clickable surface. There are no nested Claim/Buy buttons in the stamp. */
export const CaptroStamp = React.memo(function CaptroStamp({
  data, width = 232, density = 'compact', texture = false, fonts, className = '', onPress,
}: CaptroStampProps) {
  const svg = React.useMemo(() => renderStamp(data, { width, density, texture, fonts }), [data, width, density, texture, fonts]);
  const label = stampAccessibleLabel(data);
  // Safe only because renderStamp owns the geometry and escapes every dynamic field.
  // Never replace this with raw SVG/HTML submitted by a user.
  const graphic = <span className="captro-stamp__graphic" aria-hidden="true" dangerouslySetInnerHTML={{ __html: svg }} />;
  const style = { width, maxWidth: '100%', aspectRatio: density === 'compact' ? '640 / 224' : '640 / 288' };
  if (onPress) {
    return <button type="button" className={`captro-stamp ${className}`} style={style}
      aria-label={`${label}. Open details.`} onClick={() => onPress(data)}>{graphic}</button>;
  }
  return <span role="img" aria-label={label} className={`captro-stamp ${className}`} style={style}>{graphic}</span>;
});
