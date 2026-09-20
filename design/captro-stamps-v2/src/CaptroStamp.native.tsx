import * as React from 'react';
import { Platform, Pressable, View, type StyleProp, type ViewStyle } from 'react-native';
import { SvgXml } from 'react-native-svg';
import { renderStamp, stampAccessibleLabel } from './render-stamp';
import type { StampData, StampFonts, StampDensity } from './types';

export interface CaptroStampProps {
  data: StampData;
  width?: number;
  density?: StampDensity;
  texture?: boolean;
  fonts?: Partial<StampFonts>;
  style?: StyleProp<ViewStyle>;
  onPress?: (data: StampData) => void;
  /** Let the containing media manage hiding/restoring the stamp; never hide during scroll. */
  onHide?: (data: StampData) => void;
}

export const CaptroStamp = React.memo(function CaptroStamp({
  data, width = 232, density = 'compact', texture = false, fonts, style, onPress, onHide,
}: CaptroStampProps) {
  const svg = React.useMemo(() => renderStamp(data, {
    width, density, texture, native: true,
    fonts: {
      sans: Platform.OS === 'ios' ? 'Helvetica Neue' : 'sans-serif',
      serif: Platform.OS === 'ios' ? 'Georgia' : 'serif',
      ...fonts,
    },
  }), [data, width, density, texture, fonts]);
  const label = stampAccessibleLabel(data);
  const size = { width, height: width * (density === 'compact' ? 224 : 288) / 640 };
  const graphic = <View pointerEvents="none" accessible={false}
    accessibilityElementsHidden importantForAccessibility="no-hide-descendants">
    <SvgXml xml={svg} width={size.width} height={size.height} />
  </View>;

  if (onPress || onHide) {
    return <Pressable accessible accessibilityRole="button" accessibilityLabel={label}
      accessibilityHint={onPress ? 'Opens stamp details.' : 'Long press to hide this stamp.'}
      onPress={onPress ? () => onPress(data) : undefined}
      onLongPress={onHide ? () => onHide(data) : undefined}
      delayLongPress={400}
      style={({ pressed }) => [size, style, { opacity: pressed ? .86 : 1 }]}>
      {graphic}
    </Pressable>;
  }
  return <View accessible accessibilityRole="image" accessibilityLabel={label} style={[size, style]}>{graphic}</View>;
});
