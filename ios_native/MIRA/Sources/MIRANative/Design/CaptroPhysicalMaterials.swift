import SwiftUI

enum CaptroPaperKind: Equatable {
  case archival
  case linen
  case photographic
  case kraft
  case notebook
  case graph

  var assetName: String {
    self == .linen ? "CaptroLinenBoard" : "CaptroArchivalPaper"
  }
}

enum CaptroMaterialElevation {
  case flush
  case taped
  case pinned
  case photograph
  case lifted

  fileprivate var contact: (opacity: Double, radius: CGFloat, x: CGFloat, y: CGFloat) {
    switch self {
    case .flush: return (0.075, 0.7, 0.4, 0.8)
    case .taped: return (0.12, 1.1, 0.7, 1.4)
    case .pinned: return (0.16, 1.6, 0.9, 2.0)
    case .photograph: return (0.18, 2.1, 1.2, 2.8)
    case .lifted: return (0.22, 3.0, 1.8, 4.0)
    }
  }

  fileprivate var cast: (opacity: Double, radius: CGFloat, x: CGFloat, y: CGFloat) {
    switch self {
    case .flush: return (0.045, 2.0, 1.0, 2.0)
    case .taped: return (0.09, 4.0, 2.0, 4.0)
    case .pinned: return (0.12, 6.0, 2.8, 6.0)
    case .photograph: return (0.15, 8.0, 3.8, 7.5)
    case .lifted: return (0.24, 18.0, 7.0, 15.0)
    }
  }
}

enum CaptroPhysicalSeed {
  static func hash(_ value: String) -> UInt64 {
    var result: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
      result ^= UInt64(byte)
      result &*= 1_099_511_628_211
    }
    return result
  }

  static func unit(_ value: String, salt: Int) -> CGFloat {
    let mixed = hash(value) &+ UInt64(truncatingIfNeeded: salt &* 7_919)
    let scrambled = mixed &* 2_862_933_555_777_941_757 &+ 3_037_000_493
    return CGFloat(scrambled % 10_007) / 10_006
  }

  static func signed(_ value: String, salt: Int) -> CGFloat {
    (unit(value, salt: salt) * 2) - 1
  }

  static func rotation(_ value: String, salt: Int, range: ClosedRange<Double>) -> Double {
    let amount = Double(unit(value, salt: salt))
    return range.lowerBound + ((range.upperBound - range.lowerBound) * amount)
  }
}

struct CaptroPhotographedPaper: View {
  let seed: String
  let kind: CaptroPaperKind
  let base: Color
  var textureOpacity: Double = 0.24
  var directionalLight: Double = 0.18

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        base

        Image(kind.assetName, bundle: .main)
          .resizable()
          .scaledToFill()
          .frame(width: proxy.size.width, height: proxy.size.height)
          .scaleEffect(textureScale)
          .offset(textureOffset(in: proxy.size))
          .saturation(kind == .linen ? 0.72 : 0.55)
          .contrast(kind == .photographic ? 1.04 : 0.96)
          .opacity(textureOpacity)
          .blendMode(kind == .linen ? .multiply : .softLight)

        LinearGradient(
          colors: [
            Color.white.opacity(directionalLight),
            Color.clear,
            Color(red: 0.24, green: 0.15, blue: 0.08).opacity(directionalLight * 0.42),
          ],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        CaptroPaperMarks(seed: seed, kind: kind)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var textureScale: CGFloat {
    1.06 + CaptroPhysicalSeed.unit(seed, salt: 11) * 0.16
  }

  private func textureOffset(in size: CGSize) -> CGSize {
    CGSize(
      width: CaptroPhysicalSeed.signed(seed, salt: 13) * size.width * 0.055,
      height: CaptroPhysicalSeed.signed(seed, salt: 17) * size.height * 0.055
    )
  }
}

private struct CaptroPaperMarks: View {
  let seed: String
  let kind: CaptroPaperKind

  var body: some View {
    Canvas { context, size in
      if kind == .notebook || kind == .graph {
        let spacing: CGFloat = kind == .graph ? 18 : 21
        for y in stride(from: spacing, through: size.height, by: spacing) {
          var line = Path()
          line.move(to: CGPoint(x: 0, y: y))
          line.addLine(to: CGPoint(x: size.width, y: y))
          context.stroke(line, with: .color(Color.blue.opacity(kind == .graph ? 0.075 : 0.06)), lineWidth: 0.55)
        }
        if kind == .graph {
          for x in stride(from: spacing, through: size.width, by: spacing) {
            var line = Path()
            line.move(to: CGPoint(x: x, y: 0))
            line.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(line, with: .color(Color.blue.opacity(0.06)), lineWidth: 0.5)
          }
        }
      }

      for index in 0..<24 {
        let x = CaptroPhysicalSeed.unit(seed, salt: 101 + index * 3) * size.width
        let y = CaptroPhysicalSeed.unit(seed, salt: 103 + index * 5) * size.height
        let length = 3 + CaptroPhysicalSeed.unit(seed, salt: 107 + index) * 10
        var fiber = Path()
        fiber.move(to: CGPoint(x: x, y: y))
        fiber.addLine(to: CGPoint(x: min(size.width, x + length), y: y + CaptroPhysicalSeed.signed(seed, salt: 109 + index) * 1.2))
        context.stroke(fiber, with: .color(Color.black.opacity(0.022)), lineWidth: 0.55)
      }

      guard kind != .photographic else { return }
      for index in 0..<3 {
        let diameter = 22 + CaptroPhysicalSeed.unit(seed, salt: 211 + index) * 62
        let center = CGPoint(
          x: CaptroPhysicalSeed.unit(seed, salt: 223 + index) * size.width,
          y: CaptroPhysicalSeed.unit(seed, salt: 227 + index) * size.height
        )
        let rect = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter * 0.7)
        context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.39, green: 0.25, blue: 0.12).opacity(0.012)))
      }
    }
    .allowsHitTesting(false)
  }
}

struct CaptroPhysicalWallSurface: View {
  let seed: String

  var body: some View {
    CaptroPhotographedPaper(
      seed: seed,
      kind: .linen,
      base: Color(red: 0.945, green: 0.943, blue: 0.925),
      textureOpacity: 0.38,
      directionalLight: 0.16
    )
    .overlay {
      LinearGradient(
        colors: [Color.white.opacity(0.08), Color.clear, Color.black.opacity(0.035)],
        startPoint: .top,
        endPoint: .bottom
      )
      .allowsHitTesting(false)
    }
  }
}

private struct CaptroPhysicalShadowModifier: ViewModifier {
  let elevation: CaptroMaterialElevation
  let seed: String

  func body(content: Content) -> some View {
    let contact = elevation.contact
    let cast = elevation.cast
    let variance = CaptroPhysicalSeed.signed(seed, salt: 307)
    content
      .shadow(
        color: Color.black.opacity(contact.opacity),
        radius: max(0.4, contact.radius + variance * 0.25),
        x: contact.x,
        y: contact.y
      )
      .shadow(
        color: Color(red: 0.15, green: 0.10, blue: 0.06).opacity(cast.opacity),
        radius: max(1, cast.radius + variance * 1.2),
        x: cast.x + variance * 0.7,
        y: cast.y + variance * 0.8
      )
  }
}

extension View {
  func captroMaterialShadow(_ elevation: CaptroMaterialElevation, seed: String) -> some View {
    modifier(CaptroPhysicalShadowModifier(elevation: elevation, seed: seed))
  }
}

struct CaptroMaskingTape: View {
  let seed: String
  var color = Color(red: 0.82, green: 0.73, blue: 0.54)

  var body: some View {
    GeometryReader { proxy in
      let shape = CaptroTornStripShape(seed: seed)
      ZStack {
        shape
          .fill(color.opacity(0.64))

        Image("CaptroArchivalPaper", bundle: .main)
          .resizable()
          .scaledToFill()
          .opacity(0.20)
          .blendMode(.softLight)
          .clipShape(shape)

        Canvas { context, size in
          for index in 0..<7 {
            let x = size.width * CGFloat(index + 1) / 8
            let drift = CaptroPhysicalSeed.signed(seed, salt: 401 + index) * 3
            var wrinkle = Path()
            wrinkle.move(to: CGPoint(x: x + drift, y: 1))
            wrinkle.addCurve(
              to: CGPoint(x: x - drift * 0.35, y: size.height - 1),
              control1: CGPoint(x: x - 2, y: size.height * 0.34),
              control2: CGPoint(x: x + 2, y: size.height * 0.68)
            )
            context.stroke(wrinkle, with: .color(Color.white.opacity(0.16)), lineWidth: 0.65)
          }
        }
        .clipShape(shape)

        LinearGradient(
          colors: [Color.white.opacity(0.24), Color.clear, Color.black.opacity(0.07)],
          startPoint: .top,
          endPoint: .bottom
        )
        .clipShape(shape)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .captroMaterialShadow(.taped, seed: seed)
    }
    .rotationEffect(.degrees(CaptroPhysicalSeed.rotation(seed, salt: 409, range: -2.4...1.8)))
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private struct CaptroTornStripShape: Shape {
  let seed: String

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let teeth = 8
    path.move(to: CGPoint(x: 1.5, y: CaptroPhysicalSeed.unit(seed, salt: 503) * 2))
    for index in 0...teeth {
      let x = rect.width * CGFloat(index) / CGFloat(teeth)
      let y = CaptroPhysicalSeed.unit(seed, salt: 509 + index) * 1.8
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in stride(from: teeth, through: 0, by: -1) {
      let x = rect.width * CGFloat(index) / CGFloat(teeth)
      let y = rect.height - CaptroPhysicalSeed.unit(seed, salt: 541 + index) * 1.8
      path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
  }
}

struct CaptroPhotoPrintFinish: View {
  let seed: String

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Image("CaptroArchivalPaper", bundle: .main)
          .resizable()
          .scaledToFill()
          .frame(width: proxy.size.width, height: proxy.size.height)
          .opacity(0.075)
          .blendMode(.softLight)

        LinearGradient(
          colors: [Color.white.opacity(0.10), Color.clear, Color.black.opacity(0.045)],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )

        Canvas { context, size in
          for index in 0..<42 {
            let x = CaptroPhysicalSeed.unit(seed, salt: 601 + index * 2) * size.width
            let y = CaptroPhysicalSeed.unit(seed, salt: 603 + index * 3) * size.height
            let diameter = 0.35 + CaptroPhysicalSeed.unit(seed, salt: 607 + index) * 0.8
            context.fill(
              Path(ellipseIn: CGRect(x: x, y: y, width: diameter, height: diameter)),
              with: .color(Color.white.opacity(0.08))
            )
          }
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct CaptroBookGutter: View {
  var body: some View {
    GeometryReader { proxy in
      ZStack {
        LinearGradient(
          colors: [
            Color.black.opacity(0.30),
            Color(red: 0.30, green: 0.22, blue: 0.14).opacity(0.16),
            Color.white.opacity(0.34),
            Color(red: 0.29, green: 0.21, blue: 0.14).opacity(0.18),
            Color.black.opacity(0.34),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
        LinearGradient(
          colors: [Color.white.opacity(0.16), Color.clear, Color.black.opacity(0.10)],
          startPoint: .top,
          endPoint: .bottom
        )
        Rectangle().fill(Color.black.opacity(0.18)).frame(width: max(0.7, proxy.size.width * 0.08))
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .shadow(color: Color.black.opacity(0.24), radius: 6, x: 0, y: 1)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

struct CaptroPageEdgeLight: View {
  let leading: Bool

  var body: some View {
    LinearGradient(
      colors: leading
        ? [Color.black.opacity(0.11), Color.clear, Color.white.opacity(0.11)]
        : [Color.white.opacity(0.11), Color.clear, Color.black.opacity(0.11)],
      startPoint: .leading,
      endPoint: .trailing
    )
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
