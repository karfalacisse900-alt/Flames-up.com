import SwiftUI

struct MIRAWallNoteTile: View {
  let note: MIRAWallNote
  let namespace: Namespace.ID
  let isNew: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasEntered = false

  private var presentation: MIRAWallNotePresentation {
    MIRAWallNotePresentationResolver.resolve(note)
  }

  var body: some View {
    MIRAWallNoteRenderer(note: note, zoom: 1, isFocused: false)
      .matchedGeometryEffect(id: "wall-note-\(note.id)", in: namespace, isSource: true)
      .opacity(hasEntered ? 1 : initialOpacity)
      .scaleEffect(
        x: hasEntered ? 1 : initialScale.width,
        y: hasEntered ? 1 : initialScale.height,
        anchor: entranceAnchor
      )
      .offset(hasEntered ? .zero : initialOffset)
      .rotationEffect(.degrees(hasEntered ? 0 : initialEntranceRotation))
      .onAppear {
        guard !hasEntered else { return }
        if reduceMotion {
          hasEntered = true
        } else {
          withAnimation(entranceAnimation) { hasEntered = true }
        }
      }
      .onChange(of: isNew) { wasNew, isNewNow in
        guard isNewNow, !wasNew else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { hasEntered = false }
        DispatchQueue.main.async {
          if reduceMotion {
            hasEntered = true
          } else {
            withAnimation(entranceAnimation) { hasEntered = true }
          }
        }
      }
  }

  private var initialOpacity: Double {
    presentation.entrance == .reveal ? 0 : 0.72
  }

  private var initialScale: CGSize {
    if isNew { return CGSize(width: 0.72, height: 0.72) }
    switch presentation.entrance {
    case .print: return CGSize(width: 1, height: 0.18)
    case .unfold: return CGSize(width: 0.94, height: 0.48)
    case .attach: return CGSize(width: 1.05, height: 1.05)
    case .reveal: return CGSize(width: 0.98, height: 0.98)
    default: return CGSize(width: 0.94, height: 0.94)
    }
  }

  private var initialOffset: CGSize {
    if isNew { return CGSize(width: 34, height: 170) }
    switch presentation.entrance {
    case .drop: return CGSize(width: 0, height: -22)
    case .slide: return CGSize(width: presentation.microRotation < 0 ? -28 : 28, height: 8)
    case .attach: return CGSize(width: 0, height: -10)
    case .print: return CGSize(width: 0, height: -18)
    case .unfold: return CGSize(width: 0, height: -8)
    case .reveal: return CGSize(width: 0, height: 5)
    case .settle: return .zero
    }
  }

  private var entranceAnchor: UnitPoint {
    presentation.entrance == .print || presentation.entrance == .unfold ? .top : .center
  }

  private var initialEntranceRotation: Double {
    if isNew { return presentation.microRotation < 0 ? -8 : 8 }
    switch presentation.entrance {
    case .drop, .attach: return presentation.microRotation * -0.9
    case .slide: return presentation.microRotation * 1.7
    default: return 0
    }
  }

  private var entranceAnimation: Animation {
    if isNew { return .spring(response: 0.68, dampingFraction: 0.78, blendDuration: 0.04) }
    switch presentation.entrance {
    case .print: return .easeOut(duration: 0.34)
    case .reveal: return .easeOut(duration: 0.24)
    case .unfold: return .spring(response: 0.42, dampingFraction: 0.90)
    default: return .spring(response: 0.48, dampingFraction: 0.82, blendDuration: 0.02)
    }
  }
}

struct MIRAWallNoteRenderer: View {
  let note: MIRAWallNote
  let zoom: CGFloat
  let isFocused: Bool

  private var presentation: MIRAWallNotePresentation {
    MIRAWallNotePresentationResolver.resolve(note)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        MIRAWallPaperBackground(note: note, presentation: presentation)

        if presentation.style == .polaroid, let mediaURL = note.mediaThumbnailUrl ?? note.mediaUrl {
          MIRAWallPolaroidContent(note: note, mediaURL: mediaURL, zoom: zoom)
        } else {
          MIRAWallTypographyView(note: note, presentation: presentation, zoom: zoom)
        }

        MIRAWallPhysicalDetails(note: note, presentation: presentation, zoom: zoom)

        if zoom >= 0.74 {
          MIRAWallIdentityMark(note: note, style: presentation.style, zoom: zoom)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .contentShape(Rectangle())
      .shadow(
        color: .black.opacity(isFocused ? 0.24 : shadowOpacity),
        radius: isFocused ? 18 : shadowRadius,
        x: 0,
        y: isFocused ? 11 : shadowY
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(note.isGhost ? "Anonymous note" : "Note by \(note.authorPreview?.title ?? "Captro member")")
    .accessibilityValue(note.body)
  }

  private var shadowOpacity: Double {
    presentation.style == .minimal ? 0.06 : 0.15
  }

  private var shadowRadius: CGFloat {
    presentation.style == .minimal ? 2 : max(2.5, 5 * zoom)
  }

  private var shadowY: CGFloat {
    presentation.style == .minimal ? 1 : max(1.5, 3.5 * zoom)
  }
}

private struct MIRAWallPaperBackground: View {
  let note: MIRAWallNote
  let presentation: MIRAWallNotePresentation

  @ViewBuilder
  var body: some View {
    switch presentation.style {
    case .sticky:
      Rectangle()
        .fill(MIRAWallPaperColor.color(for: presentation.usesAccentColor ? note.colorToken : "cream"))
        .overlay(MIRAWallPaperGrain(seed: note.id, opacity: 0.13))
    case .editorial:
      Rectangle()
        .fill(MIRAWallPaperColor.color(for: "cream"))
        .overlay(alignment: .leading) { Rectangle().fill(Color.black.opacity(0.16)).frame(width: 2) }
        .overlay(MIRAWallPaperGrain(seed: note.id, opacity: 0.10))
    case .handwritten:
      MIRAWallSoftScrapShape(seed: note.id)
        .fill(MIRAWallPaperColor.color(for: presentation.usesAccentColor ? note.colorToken : "paper"))
        .overlay(MIRAWallPaperGrain(seed: note.id, opacity: 0.14).clipShape(MIRAWallSoftScrapShape(seed: note.id)))
    case .poster:
      Rectangle()
        .fill(presentation.usesDarkPaper ? Color(red: 0.075, green: 0.07, blue: 0.06) : MIRAWallPaperColor.color(for: presentation.usesAccentColor ? note.colorToken : "paper"))
        .overlay(Rectangle().stroke(presentation.usesDarkPaper ? Color.white.opacity(0.24) : Color.black.opacity(0.18), lineWidth: 1.2).padding(7))
    case .polaroid:
      Rectangle()
        .fill(Color(red: 0.97, green: 0.965, blue: 0.935))
        .overlay(MIRAWallPaperGrain(seed: note.id, opacity: 0.08))
    case .receipt:
      MIRAWallReceiptShape()
        .fill(Color(red: 0.965, green: 0.955, blue: 0.90))
        .overlay(MIRAWallPaperGrain(seed: note.id, opacity: 0.10).clipShape(MIRAWallReceiptShape()))
    case .tornPaper:
      MIRAWallTornPaperShape(seed: note.id)
        .fill(MIRAWallPaperColor.color(for: "paper"))
        .overlay(MIRAWallPaperGrain(seed: note.id, opacity: 0.15).clipShape(MIRAWallTornPaperShape(seed: note.id)))
    case .notebook:
      Rectangle()
        .fill(Color(red: 0.975, green: 0.965, blue: 0.91))
        .overlay(MIRAWallNotebookLines())
        .overlay(MIRAWallPaperGrain(seed: note.id, opacity: 0.07))
    case .postcard:
      Rectangle()
        .fill(Color(red: 0.92, green: 0.865, blue: 0.735))
        .overlay(MIRAWallPostcardMarks())
        .overlay(MIRAWallPaperGrain(seed: note.id, opacity: 0.17))
    case .minimal:
      Rectangle()
        .fill(Color(red: 0.965, green: 0.945, blue: 0.875).opacity(0.72))
        .overlay(alignment: .bottomLeading) {
          Rectangle().fill(Color.black.opacity(0.24)).frame(width: 42, height: 2).padding(.leading, 18).padding(.bottom, 13)
        }
    }
  }
}

private struct MIRAWallTypographyView: View {
  let note: MIRAWallNote
  let presentation: MIRAWallNotePresentation
  let zoom: CGFloat

  var body: some View {
    Group {
      switch presentation.typography {
      case .loud:
        loudTypography
      case .chaos where note.body.count <= 118:
        posterLines(mixedCase: true)
      case .editorial:
        editorialTypography
      case .thought:
        standardTypography(font: .custom("Noteworthy", size: adaptiveSize), alignment: styleAlignment)
      case .confession:
        standardTypography(font: .system(size: adaptiveSize, weight: .regular, design: .serif), alignment: styleAlignment)
      default:
        standardTypography(font: .system(size: adaptiveSize, weight: .medium, design: .monospaced), alignment: .leading)
      }
    }
    .foregroundStyle(inkColor)
    .padding(contentInsets)
  }

  private var loudTypography: some View {
    Group {
      if note.body.count <= 118 {
        posterLines(mixedCase: false)
      } else {
        standardTypography(font: .system(size: adaptiveSize, weight: .black, design: .rounded), alignment: .leading)
      }
    }
  }

  private var editorialTypography: some View {
    let pieces = editorialPieces
    return (Text(pieces.0)
      .font(.system(size: adaptiveSize, weight: note.body.count < 52 ? .bold : .semibold, design: .serif))
      + Text(pieces.1)
      .font(.system(size: max(12, adaptiveSize * 0.88), weight: .regular, design: .serif))
      .italic())
      .multilineTextAlignment(styleAlignment)
      .lineLimit(maxLineCount)
      .minimumScaleFactor(0.62)
      .allowsTightening(false)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
  }

  private func standardTypography(font: Font, alignment: TextAlignment) -> some View {
    Text(note.body)
      .font(font)
      .multilineTextAlignment(alignment)
      .lineLimit(maxLineCount)
      .minimumScaleFactor(0.58)
      .allowsTightening(false)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
  }

  private func posterLines(mixedCase: Bool) -> some View {
    let lines = MIRAWallTextComposition.lines(for: note.body, preferredCharacters: note.body.count < 48 ? 12 : 18)
    return VStack(alignment: .leading, spacing: max(1, adaptiveSize * 0.04)) {
      ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
        Text(mixedCase || index.isMultiple(of: 3) ? line : line.uppercased())
          .font(.system(
            size: max(11, adaptiveSize * (index.isMultiple(of: 3) ? 1.10 : 0.86)),
            weight: index.isMultiple(of: 2) ? .black : .bold,
            design: presentation.typography == .chaos ? .monospaced : .rounded
          ))
          .rotationEffect(.degrees(presentation.typography == .chaos && index == 1 ? -1.4 : 0))
          .lineLimit(2)
          .minimumScaleFactor(0.70)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
  }

  private var editorialPieces: (String, String) {
    guard note.body.count > 42 else { return (note.body, "") }
    let words = note.body.split(separator: " ", omittingEmptySubsequences: false)
    let split = max(2, min(words.count - 1, Int(Double(words.count) * 0.42)))
    return (words.prefix(split).joined(separator: " ") + " ", words.dropFirst(split).joined(separator: " "))
  }

  private var adaptiveSize: CGFloat {
    let length = note.body.count
    let base: CGFloat
    switch length {
    case 0...28: base = presentation.typography == .loud ? 31 : 28
    case 29...62: base = presentation.typography == .loud ? 25 : 22
    case 63...120: base = 18
    case 121...205: base = 15.5
    default: base = 13.5
    }
    let styleScale: CGFloat
    switch presentation.style {
    case .receipt: styleScale = 0.72
    case .postcard: styleScale = 0.86
    case .minimal: styleScale = 1.08
    default: styleScale = 1
    }
    return max(8, min(34, base * styleScale * max(0.82, zoom)))
  }

  private var contentInsets: EdgeInsets {
    switch presentation.style {
    case .receipt: EdgeInsets(top: 32, leading: 12, bottom: 29, trailing: 12)
    case .notebook: EdgeInsets(top: 25, leading: 30, bottom: 22, trailing: 15)
    case .postcard: EdgeInsets(top: 28, leading: 20, bottom: 22, trailing: 74)
    case .poster: EdgeInsets(top: 28, leading: 20, bottom: 22, trailing: 18)
    case .minimal: EdgeInsets(top: 16, leading: 18, bottom: 28, trailing: 18)
    default: EdgeInsets(top: 24, leading: 19, bottom: 21, trailing: 19)
    }
  }

  private var styleAlignment: TextAlignment {
    switch presentation.style {
    case .notebook, .receipt, .postcard, .editorial, .poster, .minimal: .leading
    default: .center
    }
  }

  private var frameAlignment: Alignment {
    styleAlignment == .leading ? .leading : .center
  }

  private var maxLineCount: Int {
    switch presentation.style {
    case .receipt: 22
    case .notebook: 16
    case .postcard: 9
    default: note.body.count > 170 ? 16 : 12
    }
  }

  private var inkColor: Color {
    presentation.usesDarkPaper ? Color(red: 0.98, green: 0.95, blue: 0.84) : Color(red: 0.105, green: 0.095, blue: 0.075)
  }
}

private struct MIRAWallPolaroidContent: View {
  let note: MIRAWallNote
  let mediaURL: String
  let zoom: CGFloat

  var body: some View {
    VStack(spacing: 8) {
      MIRACachedImage(url: mediaURL, maxPixelSize: 720) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        MIRAWallPaperColor.color(for: "paper")
          .overlay(Image(systemName: "photo").foregroundStyle(Color.black.opacity(0.22)))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .clipped()

      Text(note.body)
        .font(.custom("Noteworthy", size: max(11, min(19, 16 * zoom))))
        .foregroundStyle(Color(red: 0.10, green: 0.095, blue: 0.075))
        .lineLimit(3)
        .minimumScaleFactor(0.70)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
    }
    .padding(11)
    .padding(.bottom, 5)
  }
}

private struct MIRAWallPhysicalDetails: View {
  let note: MIRAWallNote
  let presentation: MIRAWallNotePresentation
  let zoom: CGFloat

  var body: some View {
    ZStack {
      attachment
      if presentation.style == .handwritten { doodles }
      if presentation.style == .receipt { receiptMetadata }
    }
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private var attachment: some View {
    switch presentation.attachment {
    case .tape:
      VStack {
        Rectangle()
          .fill(Color.white.opacity(presentation.usesDarkPaper ? 0.30 : 0.52))
          .frame(width: max(30, 50 * zoom), height: max(7, 10 * zoom))
          .rotationEffect(.degrees(presentation.microRotation * -0.7))
          .offset(y: -4)
        Spacer()
      }
    case .pin:
      VStack {
        Circle()
          .fill(pinColor)
          .frame(width: max(7, 11 * zoom), height: max(7, 11 * zoom))
          .overlay(Circle().stroke(Color.white.opacity(0.42), lineWidth: 0.8))
          .shadow(color: .black.opacity(0.24), radius: 1.5, y: 1.5)
          .offset(y: -4)
        Spacer()
      }
    case .paperclip:
      VStack {
        HStack {
          Image(systemName: "paperclip")
            .font(.system(size: max(12, 19 * zoom), weight: .medium))
            .foregroundStyle(Color.black.opacity(0.50))
            .rotationEffect(.degrees(-18))
          Spacer()
        }
        Spacer()
      }
      .padding(.leading, 8)
      .offset(y: -5)
    case .foldedCorner:
      VStack {
        HStack {
          Spacer()
          MIRAWallFoldShape()
            .fill(Color.white.opacity(0.34))
            .frame(width: max(14, 24 * zoom), height: max(14, 24 * zoom))
        }
        Spacer()
      }
    case .none:
      EmptyView()
    }
  }

  private var doodles: some View {
    ZStack {
      Image(systemName: "sparkle")
        .font(.system(size: max(8, 13 * zoom), weight: .medium))
        .rotationEffect(.degrees(-12))
        .position(x: 19, y: 25)
      Path { path in
        path.move(to: CGPoint(x: 25, y: 0))
        path.addCurve(to: CGPoint(x: 87, y: 3), control1: CGPoint(x: 42, y: -3), control2: CGPoint(x: 69, y: 8))
      }
      .stroke(Color.black.opacity(0.32), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
      .frame(width: 110, height: 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
      .padding(.trailing, 10)
      .padding(.bottom, 12)
    }
    .foregroundStyle(Color.black.opacity(0.38))
  }

  private var receiptMetadata: some View {
    VStack {
      HStack {
        Text(String(note.createdAt.prefix(10)).replacingOccurrences(of: "-", with: "."))
          .font(.system(size: max(6, 8 * zoom), weight: .regular, design: .monospaced))
          .foregroundStyle(Color.black.opacity(0.42))
        Spacer()
      }
      Spacer()
      Rectangle().fill(Color.black.opacity(0.22)).frame(height: 1)
      Text("CAPTRO / NOTE")
        .font(.system(size: max(6, 8 * zoom), weight: .medium, design: .monospaced))
        .foregroundStyle(Color.black.opacity(0.38))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 13)
  }

  private var pinColor: Color {
    let colors: [Color] = [
      Color(red: 0.70, green: 0.16, blue: 0.09),
      Color(red: 0.16, green: 0.42, blue: 0.67),
      Color(red: 0.32, green: 0.55, blue: 0.18),
      Color(red: 0.92, green: 0.66, blue: 0.12),
    ]
    let index = Int(MIRAWallNotePresentationResolver.stableHash(note.id) % UInt64(colors.count))
    return colors[index]
  }
}

private struct MIRAWallIdentityMark: View {
  let note: MIRAWallNote
  let style: MIRAWallNoteVisualStyle
  let zoom: CGFloat

  var body: some View {
    VStack {
      Spacer()
      HStack(spacing: 4) {
        Image(systemName: note.isGhost ? "theatermask.and.paintbrush" : "person.crop.circle")
        if !note.isGhost, let username = note.authorPreview?.username, !username.isEmpty, zoom > 0.96 {
          Text("@\(username)").lineLimit(1)
        }
        Spacer()
      }
      .font(.system(size: max(7, 9 * zoom), weight: .semibold))
      .foregroundStyle(style == .poster && MIRAWallNotePresentationResolver.resolve(note).usesDarkPaper ? Color.white.opacity(0.60) : Color.black.opacity(0.42))
    }
    .padding(.horizontal, style == .receipt ? 11 : 9)
    .padding(.bottom, style == .receipt ? 31 : 7)
  }
}

private struct MIRAWallPaperGrain: View {
  let seed: String
  let opacity: Double

  var body: some View {
    Canvas { context, size in
      let hash = MIRAWallNotePresentationResolver.stableHash(seed)
      for index in 0..<14 {
        let xSeed = (hash &+ UInt64(index * 7919)) % 10_000
        let ySeed = (hash &+ UInt64(index * 3571)) % 10_000
        let x = size.width * CGFloat(xSeed) / 10_000
        let y = size.height * CGFloat(ySeed) / 10_000
        let radius = CGFloat(0.45 + Double((hash &+ UInt64(index)) % 7) * 0.10)
        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)), with: .color(Color.black.opacity(opacity)))
      }
      for index in 0..<7 {
        let y = size.height * CGFloat(index + 1) / 8
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: size.width, y: y + (index.isMultiple(of: 2) ? 0.5 : -0.4)))
        context.stroke(line, with: .color(Color.black.opacity(opacity * 0.30)), lineWidth: 0.35)
      }
    }
    .allowsHitTesting(false)
  }
}

private struct MIRAWallNotebookLines: View {
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .leading) {
        Canvas { context, size in
          var y: CGFloat = 28
          while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(Color.blue.opacity(0.12)), lineWidth: 0.7)
            y += 22
          }
        }
        Rectangle().fill(Color.red.opacity(0.20)).frame(width: 1).offset(x: min(24, proxy.size.width * 0.14))
      }
    }
    .allowsHitTesting(false)
  }
}

private struct MIRAWallPostcardMarks: View {
  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .topTrailing) {
        Rectangle()
          .fill(Color.black.opacity(0.14))
          .frame(width: 1, height: proxy.size.height * 0.68)
          .offset(x: -proxy.size.width * 0.26, y: proxy.size.height * 0.18)
        RoundedRectangle(cornerRadius: 1)
          .stroke(Color.black.opacity(0.25), lineWidth: 1)
          .frame(width: 34, height: 27)
          .padding(11)
          .overlay {
            Image(systemName: "bird.fill")
              .font(.system(size: 10))
              .foregroundStyle(Color.black.opacity(0.28))
              .padding(11)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          }
      }
    }
    .allowsHitTesting(false)
  }
}

private struct MIRAWallSoftScrapShape: Shape {
  let seed: String

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + 4))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - 4, y: rect.minY + 2), control: CGPoint(x: rect.midX, y: rect.minY - 2))
    path.addQuadCurve(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 3), control: CGPoint(x: rect.maxX + 2, y: rect.midY))
    path.addQuadCurve(to: CGPoint(x: rect.minX + 4, y: rect.maxY - 1), control: CGPoint(x: rect.midX, y: rect.maxY + 3))
    path.addQuadCurve(to: CGPoint(x: rect.minX + 2, y: rect.minY + 4), control: CGPoint(x: rect.minX - 2, y: rect.midY))
    path.closeSubpath()
    return path
  }
}

private struct MIRAWallTornPaperShape: Shape {
  let seed: String

  func path(in rect: CGRect) -> Path {
    let hash = MIRAWallNotePresentationResolver.stableHash(seed)
    let segments = 10
    var points: [CGPoint] = []
    for index in 0...segments {
      let x = rect.minX + rect.width * CGFloat(index) / CGFloat(segments)
      let jitter = CGFloat(Int((hash &+ UInt64(index * 37)) % 7) - 3)
      points.append(CGPoint(x: x, y: rect.minY + 4 + jitter))
    }
    for index in 0...segments {
      let y = rect.minY + rect.height * CGFloat(index) / CGFloat(segments)
      let jitter = CGFloat(Int((hash &+ UInt64(index * 53)) % 7) - 3)
      points.append(CGPoint(x: rect.maxX - 4 + jitter, y: y))
    }
    for index in (0...segments).reversed() {
      let x = rect.minX + rect.width * CGFloat(index) / CGFloat(segments)
      let jitter = CGFloat(Int((hash &+ UInt64(index * 71)) % 7) - 3)
      points.append(CGPoint(x: x, y: rect.maxY - 4 + jitter))
    }
    for index in (0...segments).reversed() {
      let y = rect.minY + rect.height * CGFloat(index) / CGFloat(segments)
      let jitter = CGFloat(Int((hash &+ UInt64(index * 89)) % 7) - 3)
      points.append(CGPoint(x: rect.minX + 4 + jitter, y: y))
    }
    var path = Path()
    if let first = points.first { path.move(to: first) }
    for point in points.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
  }
}

private struct MIRAWallReceiptShape: Shape {
  func path(in rect: CGRect) -> Path {
    let tooth: CGFloat = 8
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + tooth))
    var x = rect.minX
    var raised = false
    while x <= rect.maxX {
      path.addLine(to: CGPoint(x: x, y: rect.minY + (raised ? 0 : tooth)))
      raised.toggle()
      x += tooth
    }
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tooth))
    raised = false
    x = rect.maxX
    while x >= rect.minX {
      path.addLine(to: CGPoint(x: x, y: rect.maxY - (raised ? 0 : tooth)))
      raised.toggle()
      x -= tooth
    }
    path.closeSubpath()
    return path
  }
}

private struct MIRAWallFoldShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
    path.closeSubpath()
    return path
  }
}

enum MIRAWallPaperColor {
  static func color(for token: String) -> Color {
    switch token {
    case "cream": Color(red: 0.96, green: 0.93, blue: 0.84)
    case "rose": Color(red: 0.93, green: 0.72, blue: 0.75)
    case "sky": Color(red: 0.70, green: 0.84, blue: 0.86)
    case "mint": Color(red: 0.75, green: 0.85, blue: 0.69)
    case "peach": Color(red: 0.94, green: 0.77, blue: 0.61)
    case "paper": Color(red: 0.94, green: 0.925, blue: 0.86)
    default: Color(red: 0.94, green: 0.83, blue: 0.43)
    }
  }
}

enum MIRAWallTextComposition {
  static func lines(for text: String, preferredCharacters: Int) -> [String] {
    let words = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    guard !words.isEmpty else { return [] }
    var lines: [String] = []
    var current = ""
    for word in words {
      let candidate = current.isEmpty ? word : "\(current) \(word)"
      if candidate.count > preferredCharacters, current.count > 2 {
        lines.append(current)
        current = word
      } else {
        current = candidate
      }
    }
    if !current.isEmpty { lines.append(current) }
    if lines.count > 1, let last = lines.last, last.count <= 2 {
      lines[lines.count - 2] += " \(last)"
      lines.removeLast()
    }
    return lines
  }
}
