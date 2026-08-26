import SwiftUI
import UIKit

// Codename kept as `MIRATheme` (the module is still `MIRANative`); this is the shared design
// token set for Aura Mobile. Renaming the type itself would ripple through every screen file
// for no functional benefit, so only the Captro-specific values inside it are being replaced.
public enum MIRATheme {
  public enum Color {
    public static let appBackground = adaptive(
      light: UIColor(red: 0.961, green: 0.957, blue: 0.945, alpha: 1),
      dark: UIColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 1)
    )
    public static let launchBackground = adaptive(
      light: UIColor(red: 0.961, green: 0.957, blue: 0.941, alpha: 1),
      dark: UIColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 1)
    )
    public static let surface = adaptive(
      light: UIColor.white,
      dark: UIColor(red: 0.043, green: 0.043, blue: 0.050, alpha: 1)
    )
    public static let surfaceSoft = adaptive(
      light: UIColor(red: 0.949, green: 0.945, blue: 0.929, alpha: 1),
      dark: UIColor(red: 0.078, green: 0.078, blue: 0.086, alpha: 1)
    )
    public static let surfaceRaised = adaptive(
      light: UIColor.white,
      dark: UIColor(red: 0.105, green: 0.105, blue: 0.115, alpha: 1)
    )
    public static let mediaPlaceholder = adaptive(
      light: UIColor(red: 0.875, green: 0.872, blue: 0.838, alpha: 1),
      dark: UIColor(red: 0.105, green: 0.105, blue: 0.112, alpha: 1)
    )
    public static let mediaPlaceholderRaised = adaptive(
      light: UIColor(red: 0.948, green: 0.944, blue: 0.904, alpha: 1),
      dark: UIColor(red: 0.150, green: 0.150, blue: 0.158, alpha: 1)
    )
    public static let textPrimary = adaptive(
      light: UIColor(red: 0.067, green: 0.067, blue: 0.067, alpha: 1),
      dark: UIColor(red: 0.955, green: 0.955, blue: 0.960, alpha: 1)
    )
    public static let textSecondary = adaptive(
      light: UIColor(red: 0.373, green: 0.373, blue: 0.373, alpha: 1),
      dark: UIColor(red: 0.705, green: 0.705, blue: 0.730, alpha: 1)
    )
    public static let textMuted = adaptive(
      light: UIColor(red: 0.545, green: 0.545, blue: 0.545, alpha: 1),
      dark: UIColor(red: 0.500, green: 0.500, blue: 0.525, alpha: 1)
    )
    public static let forest = adaptive(
      light: UIColor(red: 0.310, green: 0.463, blue: 0.314, alpha: 1),
      dark: UIColor(red: 0.360, green: 0.760, blue: 0.470, alpha: 1)
    )
    public static let forestSoft = adaptive(
      light: UIColor(red: 0.878, green: 0.925, blue: 0.847, alpha: 1),
      dark: UIColor(red: 0.055, green: 0.095, blue: 0.065, alpha: 1)
    )
    public static let auraViolet = adaptive(
      light: UIColor(red: 0.369, green: 0.247, blue: 0.847, alpha: 1),
      dark: UIColor(red: 0.625, green: 0.500, blue: 1.000, alpha: 1)
    )
    public static let auraVioletSoft = adaptive(
      light: UIColor(red: 0.941, green: 0.925, blue: 0.988, alpha: 1),
      dark: UIColor(red: 0.110, green: 0.070, blue: 0.210, alpha: 1)
    )
    public static let accent = SwiftUI.Color(red: 0.478, green: 0.608, blue: 0.416)
    public static let like = SwiftUI.Color(red: 0.875, green: 0.305, blue: 0.440)
    public static let divider = adaptive(
      light: UIColor.black.withAlphaComponent(0.090),
      dark: UIColor.white.withAlphaComponent(0.095)
    )
    public static let hairline = adaptive(
      light: UIColor.black.withAlphaComponent(0.120),
      dark: UIColor.white.withAlphaComponent(0.080)
    )

    private static func adaptive(light: UIColor, dark: UIColor) -> SwiftUI.Color {
      SwiftUI.Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? dark : light
      })
    }
  }

  public enum Radius {
    public static let small: CGFloat = 10
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 24
    public static let sheet: CGFloat = 28
  }

  public enum Space {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
  }

  public static func softShadow() -> some ViewModifier {
    SurfaceShadow(radius: 24, y: 8, opacity: 0.075)
  }

  public static func floatingShadow() -> some ViewModifier {
    SurfaceShadow(radius: 34, y: 14, opacity: 0.110)
  }
}

public struct SurfaceShadow: ViewModifier {
  let radius: CGFloat
  let y: CGFloat
  let opacity: Double

  public func body(content: Content) -> some View {
    content.shadow(color: SwiftUI.Color.black.opacity(opacity), radius: radius, x: 0, y: y)
  }
}

public extension View {
  func miraCardSurface(cornerRadius: CGFloat = MIRATheme.Radius.large) -> some View {
    self
      .background(MIRATheme.Color.surface)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
      .modifier(MIRATheme.softShadow())
  }
}
