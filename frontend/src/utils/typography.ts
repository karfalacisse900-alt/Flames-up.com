import { Platform, Text, TextInput } from 'react-native';

export const appFontFamily = Platform.select({
  web: '"Google Sans Flex", "Google Sans", Roboto, Arial, sans-serif',
  ios: 'System',
  android: 'sans-serif',
  default: 'sans-serif',
});

export const appTextDefaults = {
  fontFamily: appFontFamily,
  fontWeight: '400' as const,
  letterSpacing: 0,
};

let configured = false;

export function configureTypographyDefaults() {
  if (configured) return;
  configured = true;

  const textComponent = Text as typeof Text & { defaultProps?: Record<string, any> };
  const inputComponent = TextInput as typeof TextInput & { defaultProps?: Record<string, any> };

  textComponent.defaultProps = textComponent.defaultProps || {};
  textComponent.defaultProps.style = [appTextDefaults, textComponent.defaultProps.style].filter(Boolean);

  inputComponent.defaultProps = inputComponent.defaultProps || {};
  inputComponent.defaultProps.style = [appTextDefaults, inputComponent.defaultProps.style].filter(Boolean);
}
