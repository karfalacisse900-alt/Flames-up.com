import SwiftUI
import UIKit

public enum MIRATheme {
  public enum Color {
    public static let appBackground = adaptive(
      light: UIColor.white,
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
      light: UIColor(red: 0.982, green: 0.985, blue: 0.978, alpha: 1),
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
      light: UIColor(red: 0.070, green: 0.084, blue: 0.068, alpha: 1),
      dark: UIColor(red: 0.955, green: 0.955, blue: 0.960, alpha: 1)
    )
    public static let textSecondary = adaptive(
      light: UIColor(red: 0.405, green: 0.440, blue: 0.390, alpha: 1),
      dark: UIColor(red: 0.705, green: 0.705, blue: 0.730, alpha: 1)
    )
    public static let textMuted = adaptive(
      light: UIColor(red: 0.595, green: 0.625, blue: 0.570, alpha: 1),
      dark: UIColor(red: 0.500, green: 0.500, blue: 0.525, alpha: 1)
    )
    public static let forest = adaptive(
      light: UIColor(red: 0.090, green: 0.175, blue: 0.105, alpha: 1),
      dark: UIColor(red: 0.360, green: 0.760, blue: 0.470, alpha: 1)
    )
    public static let forestSoft = adaptive(
      light: UIColor(red: 0.925, green: 0.965, blue: 0.905, alpha: 1),
      dark: UIColor(red: 0.055, green: 0.095, blue: 0.065, alpha: 1)
    )
    public static let accent = SwiftUI.Color(red: 0.365, green: 0.785, blue: 0.500)
    public static let like = SwiftUI.Color(red: 0.875, green: 0.305, blue: 0.440)
    public static let divider = adaptive(
      light: UIColor.black.withAlphaComponent(0.055),
      dark: UIColor.white.withAlphaComponent(0.095)
    )
    public static let hairline = adaptive(
      light: UIColor(red: 0.120, green: 0.160, blue: 0.110, alpha: 0.060),
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
