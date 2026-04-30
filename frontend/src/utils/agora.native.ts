declare const require: (moduleName: string) => unknown;

export type AgoraModule = any;

export function loadAgoraModule(): AgoraModule | null {
  try {
    const agora = require('react-native-agora') as AgoraModule;
    // Touch native-backed exports inside this guard so Expo Go or an old dev build
    // shows our friendly fallback instead of the SDK's red-screen linking error.
    if (!agora.createAgoraRtcEngine || !agora.RtcSurfaceView) return null;
    return agora;
  } catch {
    return null;
  }
}
