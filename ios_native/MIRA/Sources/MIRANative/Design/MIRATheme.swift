import SwiftUI

public enum MIRATheme {
  public enum Color {
    public static let appBackground = SwiftUI.Color.white
    public static let surface = SwiftUI.Color.white
    public static let surfaceSoft = SwiftUI.Color(red: 0.982, green: 0.985, blue: 0.978)
    public static let surfaceRaised = SwiftUI.Color.white
    public static let textPrimary = SwiftUI.Color(red: 0.070, green: 0.084, blue: 0.068)
    public static let textSecondary = SwiftUI.Color(red: 0.405, green: 0.440, blue: 0.390)
    public static let textMuted = SwiftUI.Color(red: 0.595, green: 0.625, blue: 0.570)
    public static let forest = SwiftUI.Color(red: 0.090, green: 0.175, blue: 0.105)
    public static let forestSoft = SwiftUI.Color(red: 0.925, green: 0.965, blue: 0.905)
    public static let accent = SwiftUI.Color(red: 0.365, green: 0.785, blue: 0.500)
    public static let like = SwiftUI.Color(red: 0.875, green: 0.305, blue: 0.440)
    public static let divider = SwiftUI.Color.black.opacity(0.055)
    public static let hairline = SwiftUI.Color(red: 0.120, green: 0.160, blue: 0.110).opacity(0.060)
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
