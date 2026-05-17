import SwiftUI

public enum MIRATheme {
  public enum Color {
    public static let appBackground = SwiftUI.Color.white
    public static let surface = SwiftUI.Color.white
    public static let surfaceSoft = SwiftUI.Color(red: 0.970, green: 0.975, blue: 0.965)
    public static let surfaceRaised = SwiftUI.Color.white
    public static let textPrimary = SwiftUI.Color(red: 0.075, green: 0.088, blue: 0.072)
    public static let textSecondary = SwiftUI.Color(red: 0.430, green: 0.465, blue: 0.410)
    public static let textMuted = SwiftUI.Color(red: 0.610, green: 0.635, blue: 0.580)
    public static let forest = SwiftUI.Color(red: 0.090, green: 0.175, blue: 0.105)
    public static let forestSoft = SwiftUI.Color(red: 0.900, green: 0.950, blue: 0.885)
    public static let accent = SwiftUI.Color(red: 0.510, green: 0.815, blue: 0.565)
    public static let divider = SwiftUI.Color.black.opacity(0.055)
    public static let hairline = SwiftUI.Color(red: 0.120, green: 0.160, blue: 0.110).opacity(0.075)
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
    SurfaceShadow(radius: 22, y: 7, opacity: 0.060)
  }

  public static func floatingShadow() -> some ViewModifier {
    SurfaceShadow(radius: 32, y: 12, opacity: 0.090)
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
