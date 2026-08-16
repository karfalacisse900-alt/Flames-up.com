import SwiftUI

public enum NoteCanvasRenderMode: Equatable {
  case wall
  case detail
  case editor(selectedElementID: String?)
}

public struct NoteCanvasRenderer: View {
  public let document: NoteDocument
  public let mode: NoteCanvasRenderMode
  public let onPhotoTapped: ((PhotoElement, CGRect) -> Void)?

  public init(
    document: NoteDocument,
    mode: NoteCanvasRenderMode = .detail,
    onPhotoTapped: ((PhotoElement, CGRect) -> Void)? = nil
  ) {
    self.document = document
    self.mode = mode
    self.onPhotoTapped = onPhotoTapped
  }

  public var body: some View {
    GeometryReader { proxy in
      let width = max(1, proxy.size.width)
      let scale = width / max(1, document.canvas.designWidth)
      let height = document.canvas.designHeight * scale

      ZStack {
        NoteCanvasBackgroundView(background: document.canvas.background)
          .frame(width: width, height: height)

        ForEach(visibleElements) { element in
          NoteCanvasElementView(
            element: element,
            scale: scale,
            mode: mode,
            onPhotoTapped: onPhotoTapped
          )
        }
      }
      .frame(width: width, height: height)
      .clipShape(canvasClipShape)
      .contentShape(Rectangle())
      .accessibilityElement(children: .contain)
      .accessibilityLabel(document.altText ?? document.caption ?? "Note artwork")
    }
    .aspectRatio(document.canvasAspectRatio, contentMode: .fit)
  }

  private var visibleElements: [CanvasElement] {
    document.canvas.elements
      .filter { !$0.isHidden }
      .sorted {
        if $0.transform.zIndex == $1.transform.zIndex { return $0.id < $1.id }
        return $0.transform.zIndex < $1.transform.zIndex
      }
  }

  private var canvasClipShape: RoundedRectangle {
    switch mode {
    case .wall:
      return RoundedRectangle(cornerRadius: 7, style: .continuous)
    case .detail, .editor:
      return RoundedRectangle(cornerRadius: 10, style: .continuous)
    }
  }
}

private struct NoteCanvasElementView: View {
  let element: CanvasElement
  let scale: CGFloat
  let mode: NoteCanvasRenderMode
  let onPhotoTapped: ((PhotoElement, CGRect) -> Void)?

  var body: some View {
    elementBody
      .frame(width: element.transform.width * scale, height: element.transform.height * scale)
      .opacity(element.transform.opacity)
      .scaleEffect(x: element.transform.scaleX, y: element.transform.scaleY)
      .rotationEffect(.degrees(element.transform.rotation))
      .position(
        x: (element.transform.x + element.transform.width / 2) * scale,
        y: (element.transform.y + element.transform.height / 2) * scale
      )
      .overlay(selectionOverlay)
      .accessibilityLabel(element.accessibilityLabel ?? accessibilityFallback)
  }

  @ViewBuilder
  private var elementBody: some View {
    switch element.kind {
    case .photo:
      if let photo = element.photo {
        photoView(photo)
      }
    case .text:
      if let text = element.text {
        textView(text)
      }
    case .paper:
      materialPaper
    case .tape:
      tapeView
    case .shape:
      if let shape = element.shape {
        shapeView(shape)
      }
    case .sticker:
      stickerView
    case .drawing:
      drawingView
    case .group:
      Color.clear
    }
  }

  @ViewBuilder
  private func photoView(_ photo: PhotoElement) -> some View {
    GeometryReader { proxy in
      let frame = proxy.frame(in: .global)
      let media = RemoteMediaView(
        url: photo.url,
        isVideo: false,
        contentMode: photo.presentation == .borderless || photo.presentation == .fullBleed ? .fill : .fill,
        maxPixelSize: mode == .wall ? 900 : 1800,
        placeholderColor: MIRATheme.Color.surfaceSoft,
        placeholderTint: MIRATheme.Color.textMuted
      )

      Group {
        if let onPhotoTapped {
          Button {
            onPhotoTapped(photo, frame)
          } label: {
            photoSurface(media, style: photo.presentation)
          }
          .buttonStyle(.plain)
        } else {
          photoSurface(media, style: photo.presentation)
        }
      }
    }
  }

  @ViewBuilder
  private func photoSurface(_ media: RemoteMediaView, style: PhotoPresentationStyle) -> some View {
    switch style {
    case .polaroid:
      VStack(spacing: 0) {
        media
          .padding(.top, 28)
          .padding(.horizontal, 28)
        Rectangle()
          .fill(.white)
          .frame(height: 78)
      }
      .background(.white)
      .shadow(color: .black.opacity(0.14), radius: 13, x: 0, y: 6)
    case .printed:
      media
        .padding(18)
        .background(Color.white)
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 4)
    case .rounded:
      media
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    case .circle:
      media
        .clipShape(Circle())
    case .arch:
      media
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 260, bottomLeadingRadius: 26, bottomTrailingRadius: 26, topTrailingRadius: 260, style: .continuous))
    case .tornEdge:
      media
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(TornEdgeOverlay().stroke(Color.white.opacity(0.85), lineWidth: 12))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    case .borderless, .fullBleed, .cutout:
      media
    }
  }

  private func textView(_ text: TextElement) -> some View {
    Text(text.uppercase ? text.text.uppercased() : text.text)
      .font(.system(size: text.size * scale, weight: text.weight.swiftUIFontWeight, design: text.role == .title ? .serif : .default))
      .tracking(text.letterSpacing * scale)
      .lineSpacing(max(0, text.lineSpacing * scale))
      .multilineTextAlignment(text.alignment.swiftUITextAlignment)
      .foregroundStyle(Color.miraHex(text.color))
      .minimumScaleFactor(0.25)
      .padding(text.backgroundColor == nil ? 0 : 14 * scale)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: text.alignment.swiftAlignment)
      .background {
        if let background = text.backgroundColor {
          RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
            .fill(Color.miraHex(background))
        }
      }
  }

  @ViewBuilder
  private var materialPaper: some View {
    NoteMaterialSurface(material: element.material ?? .creamPaper)
      .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 5)
  }

  private var tapeView: some View {
    RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
      .fill(Color.white.opacity(0.46))
      .overlay {
        LinearGradient(colors: [.white.opacity(0.28), .clear, .white.opacity(0.18)], startPoint: .topLeading, endPoint: .bottomTrailing)
      }
      .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
  }

  @ViewBuilder
  private func shapeView(_ shape: ShapeElement) -> some View {
    switch shape.shape {
    case .ellipse:
      Ellipse()
        .fill(Color.miraHex(shape.fill))
        .overlay(Ellipse().stroke(Color.miraHex(shape.stroke ?? "#00000000"), lineWidth: shape.strokeWidth * scale))
    case .line:
      Rectangle()
        .fill(Color.miraHex(shape.fill))
        .frame(height: max(1, shape.strokeWidth * scale))
    case .rectangle:
      RoundedRectangle(cornerRadius: shape.cornerRadius * scale, style: .continuous)
        .fill(Color.miraHex(shape.fill))
        .overlay(RoundedRectangle(cornerRadius: shape.cornerRadius * scale, style: .continuous).stroke(Color.miraHex(shape.stroke ?? "#00000000"), lineWidth: shape.strokeWidth * scale))
    }
  }

  private var stickerView: some View {
    RoundedRectangle(cornerRadius: 20 * scale, style: .continuous)
      .fill(Color.miraHex("#FCEB75"))
      .overlay {
        if element.preset == .highlightStrip {
          Color.miraHex("#FFE45A").opacity(0.72)
        }
      }
  }

  private var drawingView: some View {
    Path { path in
      path.move(to: CGPoint(x: 0, y: element.transform.height * scale * 0.6))
      path.addCurve(
        to: CGPoint(x: element.transform.width * scale, y: element.transform.height * scale * 0.42),
        control1: CGPoint(x: element.transform.width * scale * 0.26, y: 0),
        control2: CGPoint(x: element.transform.width * scale * 0.72, y: element.transform.height * scale)
      )
    }
    .stroke(Color.miraHex("#1A1A16"), lineWidth: max(1.5, 5 * scale))
  }

  @ViewBuilder
  private var selectionOverlay: some View {
    if case .editor(let selectedID) = mode, selectedID == element.id {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(MIRATheme.Color.forest, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
        .shadow(color: MIRATheme.Color.forest.opacity(0.18), radius: 10, x: 0, y: 0)
    }
  }

  private var accessibilityFallback: String {
    switch element.kind {
    case .photo: return "Photo element"
    case .text: return element.text?.text ?? "Text element"
    case .paper: return "Paper element"
    case .tape: return "Tape element"
    case .sticker: return "Sticker element"
    case .drawing: return "Drawing element"
    case .shape: return "Shape element"
    case .group: return "Group element"
    }
  }
}

private struct NoteCanvasBackgroundView: View {
  let background: CanvasBackground

  var body: some View {
    ZStack {
      switch background {
      case .solid(let color):
        Color.miraHex(color)
      case .gradient(let colors):
        LinearGradient(
          colors: colors.map(Color.miraHex),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
      case .image(let url):
        RemoteMediaView(url: url, isVideo: false, contentMode: .fill, maxPixelSize: 1600)
      case .material(let material):
        NoteMaterialSurface(material: material)
      }
    }
  }
}

private struct NoteMaterialSurface: View {
  let material: NoteMaterial

  var body: some View {
    ZStack {
      base
      if material == .notebookPaper {
        VStack(spacing: 34) {
          ForEach(0..<24, id: \.self) { _ in
            Rectangle()
              .fill(Color.blue.opacity(0.08))
              .frame(height: 1)
          }
        }
        .padding(.top, 28)
      }
      if material != .blackLeather && material != .darkCardstock {
        Canvas { context, size in
          for index in 0..<60 {
            let x = CGFloat((index * 37) % 997) / 997 * size.width
            let y = CGFloat((index * 53) % 991) / 991 * size.height
            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(.black.opacity(0.025)))
          }
        }
      }
    }
  }

  @ViewBuilder
  private var base: some View {
    switch material {
    case .creamPaper:
      Color.miraHex("#F4E8D1")
    case .whiteCottonPaper:
      Color.miraHex("#FBFAF5")
    case .agedPaper:
      LinearGradient(colors: [Color.miraHex("#E9D1A8"), Color.miraHex("#F5E6C7")], startPoint: .topLeading, endPoint: .bottomTrailing)
    case .linen:
      Color.miraHex("#E8E1D2")
    case .notebookPaper:
      Color.miraHex("#FAF8EE")
    case .blackLeather:
      LinearGradient(colors: [Color.miraHex("#11110F"), Color.miraHex("#24211C")], startPoint: .top, endPoint: .bottom)
    case .darkCardstock:
      Color.miraHex("#171A17")
    case .watercolorPaper:
      LinearGradient(colors: [Color.miraHex("#F8F3E8"), Color.miraHex("#E7F0EA")], startPoint: .topLeading, endPoint: .bottomTrailing)
    case .softNeutralPosterPaper:
      Color.miraHex("#F6F2EA")
    }
  }
}

private struct TornEdgeOverlay: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + 8))
    let steps = 16
    for index in 0...steps {
      let x = rect.minX + rect.width * CGFloat(index) / CGFloat(steps)
      let y = rect.minY + CGFloat((index * 17) % 9)
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in 0...steps {
      let y = rect.minY + rect.height * CGFloat(index) / CGFloat(steps)
      let x = rect.maxX - CGFloat((index * 13) % 8)
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in stride(from: steps, through: 0, by: -1) {
      let x = rect.minX + rect.width * CGFloat(index) / CGFloat(steps)
      let y = rect.maxY - CGFloat((index * 11) % 10)
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in stride(from: steps, through: 0, by: -1) {
      let y = rect.minY + rect.height * CGFloat(index) / CGFloat(steps)
      let x = rect.minX + CGFloat((index * 19) % 7)
      path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
  }
}

public struct NoteMediaViewer: View {
  public let photo: PhotoElement
  public let onClose: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var scale: CGFloat = 1
  @State private var offset: CGSize = .zero

  public init(photo: PhotoElement, onClose: @escaping () -> Void) {
    self.photo = photo
    self.onClose = onClose
  }

  public var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.black.ignoresSafeArea()
      RemoteMediaView(
        url: photo.originalUrl ?? photo.url,
        isVideo: false,
        contentMode: .fit,
        maxPixelSize: 2400,
        placeholderColor: .black,
        placeholderTint: .white.opacity(0.68)
      )
      .scaleEffect(scale)
      .offset(offset)
      .gesture(
        MagnificationGesture()
          .onChanged { value in
            scale = min(max(1, value), 4)
          }
      )
      .simultaneousGesture(
        DragGesture(minimumDistance: 8)
          .onChanged { value in
            offset = value.translation
          }
          .onEnded { value in
            if value.translation.height > 120 && scale <= 1.05 {
              onClose()
            } else {
              withAnimation(.easeOut(duration: reduceMotion ? 0.05 : 0.18)) {
                offset = .zero
              }
            }
          }
      )

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white)
          .frame(width: 44, height: 44)
          .background(.black.opacity(0.46))
          .clipShape(Circle())
      }
      .padding(.top, 16)
      .padding(.trailing, 16)
      .accessibilityLabel("Close photo")
    }
  }
}

public extension Color {
  static func miraHex(_ value: String) -> Color {
    let trimmed = value.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    guard let number = UInt64(trimmed, radix: 16) else { return .clear }
    switch trimmed.count {
    case 8:
      let red = Double((number >> 24) & 0xff) / 255
      let green = Double((number >> 16) & 0xff) / 255
      let blue = Double((number >> 8) & 0xff) / 255
      let alpha = Double(number & 0xff) / 255
      return Color(red: red, green: green, blue: blue, opacity: alpha)
    case 6:
      let red = Double((number >> 16) & 0xff) / 255
      let green = Double((number >> 8) & 0xff) / 255
      let blue = Double(number & 0xff) / 255
      return Color(red: red, green: green, blue: blue)
    default:
      return .clear
    }
  }
}

private extension TextWeight {
  var swiftUIFontWeight: Font.Weight {
    switch self {
    case .regular: return .regular
    case .medium: return .medium
    case .semibold: return .semibold
    case .bold: return .bold
    case .heavy: return .heavy
    }
  }
}

private extension TextAlignmentValue {
  var swiftUITextAlignment: TextAlignment {
    switch self {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
  }

  var swiftAlignment: Alignment {
    switch self {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
  }
}
