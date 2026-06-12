import SwiftUI

public enum MIRAAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }

  public var systemImage: String {
    switch self {
    case .system: return "circle.lefthalf.filled"
    case .light: return "sun.max"
    case .dark: return "moon"
    }
  }
}

public enum MIRAAppearanceResolver {
  public static let preferenceKey = "captro.appearance.preference"

  public static func storedPreference() -> String {
    let raw = UserDefaults.standard.string(forKey: preferenceKey) ?? MIRAAppearance.system.rawValue
    return MIRAAppearance(rawValue: raw)?.rawValue ?? MIRAAppearance.system.rawValue
  }

  public static func colorScheme(for rawValue: String) -> ColorScheme? {
    switch MIRAAppearance(rawValue: rawValue) ?? .system {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}
