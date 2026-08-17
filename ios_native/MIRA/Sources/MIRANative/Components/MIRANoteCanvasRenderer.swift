import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum MIRANoteCanvasRenderMode: Equatable {
  case wallPreview
  case detail
  case editor

  var textureDetail: Double {
    switch self {
    case .wallPreview:
      // The Wall is a true scale preview of the authored document. Keeping
      // most of the material contrast here prevents paper, tape, and print
      // borders from collapsing into flat beige rectangles when zoomed out.
      return 0.88
    case .detail, .editor:
      return 1
    }
  }
}

/// Renders a note in one immutable design coordinate space. The complete
/// document is laid out at its authored size, then scaled as a single surface.
/// Text therefore never reflows when the Wall zoom changes.
struct MIRANoteCanvasRenderer: View {
  let canvas: MIRANoteCanvas
  var mode: MIRANoteCanvasRenderMode = .wallPreview
  var localImages: [String: UIImage] = [:]
  var selectedElementID: String? = nil
  var onSelectElement: ((String) -> Void)? = nil
  var onOpenPhoto: ((MIRANoteCanvasElement) -> Void)? = nil

  var body: some View {
    GeometryReader { proxy in
      let designSize = CGSize(
        width: CGFloat(max(1, canvas.designWidth)),
        height: CGFloat(max(1, canvas.designHeight))
      )
      let scale = min(
        proxy.size.width / designSize.width,
        proxy.size.height / designSize.height
      )
      let renderedSize = CGSize(
        width: designSize.width * scale,
        height: designSize.height * scale
      )

      ZStack(alignment: .topLeading) {
        canvasBackground
          .frame(width: designSize.width, height: designSize.height)

        ForEach(canvas.orderedElements) { element in
          elementView(element, designSize: designSize)
            .frame(
              width: max(4, CGFloat(element.width) * designSize.width),
              height: max(4, CGFloat(element.height) * designSize.height)
            )
            .position(
              x: CGFloat(element.x) * designSize.width,
              y: CGFloat(element.y) * designSize.height
            )
            .rotationEffect(.degrees(element.rotation))
            .opacity(element.opacity)
            .zIndex(Double(element.zIndex))
        }
      }
      .frame(width: designSize.width, height: designSize.height, alignment: .topLeading)
      .clipped()
      .scaleEffect(scale, anchor: .topLeading)
      .frame(width: renderedSize.width, height: renderedSize.height, alignment: .topLeading)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
    .aspectRatio(CGFloat(canvas.aspectRatio), contentMode: .fit)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var canvasBackground: some View {
    if let asset = CaptroNoteAsset.resolve(canvas.background.textureAsset) {
      ZStack {
        canvasColor(canvas.background.colorHex, fallback: backgroundFallback)
        CaptroNoteAssetView(asset: asset, contentMode: .fill)
          .saturation(mode == .wallPreview ? 0.96 : 1)
          .contrast(mode == .wallPreview ? 1.03 : 1)
      }
      .clipped()
    } else {
      CaptroPhotographedPaper(
        seed: "canvas-\(canvas.version)-\(canvas.template.rawValue)",
        kind: paperKind(canvas.background.material),
        base: canvasColor(canvas.background.colorHex, fallback: backgroundFallback),
        textureOpacity: 0.34 * mode.textureDetail,
        directionalLight: canvas.template == .darkAlbum ? 0.08 : 0.16
      )
      .overlay {
        if canvas.template == .notebook {
          notebookMargin
        }
      }
    }
  }

  private var notebookMargin: some View {
    GeometryReader { proxy in
      Path { path in
        path.move(to: CGPoint(x: proxy.size.width * 0.11, y: 0))
        path.addLine(to: CGPoint(x: proxy.size.width * 0.11, y: proxy.size.height))
      }
      .stroke(Color.red.opacity(0.18), lineWidth: 2)
    }
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private func elementView(_ element: MIRANoteCanvasElement, designSize: CGSize) -> some View {
    let selected = selectedElementID == element.id

    Group {
      switch element.kind {
      case .photo:
        photoElement(element, polaroid: false)
      case .polaroid:
        photoElement(element, polaroid: true)
      case .text, .handwrittenCaption:
        textElement(element)
      case .tornPaper:
        paperElement(element, torn: true)
      case .texturedPaper:
        paperElement(element, torn: false)
      case .tape:
        if let asset = CaptroNoteAsset.resolve(element.style.material) {
          CaptroNoteAssetView(asset: asset)
        } else {
          CaptroMaskingTape(
            seed: element.id,
            color: canvasColor(element.style.colorHex, fallback: Color(red: 0.83, green: 0.75, blue: 0.58))
          )
        }
      case .sticker:
        stickerElement(element)
      case .drawing:
        drawingElement(element)
      case .flower:
        flowerElement(element)
      case .shape:
        shapeElement(element)
      }
    }
    .overlay {
      if selected && mode == .editor {
        RoundedRectangle(cornerRadius: 12)
          .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, dash: [14, 8]))
          .padding(-7)
          .allowsHitTesting(false)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      guard mode != .wallPreview else { return }
      if mode == .editor {
        onSelectElement?(element.id)
      } else if element.kind == .photo || element.kind == .polaroid {
        onOpenPhoto?(element)
      }
    }
    .accessibilityLabel(accessibilityLabel(for: element))
  }

  @ViewBuilder
  private func photoElement(_ element: MIRANoteCanvasElement, polaroid: Bool) -> some View {
    if polaroid {
      GeometryReader { proxy in
        let border = max(14, proxy.size.width * 0.055)
        let captionHeight = element.text?.isEmpty == false ? max(42, proxy.size.height * 0.16) : border

        ZStack(alignment: .top) {
          CaptroPhotographedPaper(
            seed: "polaroid-\(element.id)",
            kind: .photographic,
            base: Color(red: 0.975, green: 0.965, blue: 0.925),
            textureOpacity: 0.20 * mode.textureDetail,
            directionalLight: 0.12
          )

          mediaImage(element)
            .frame(
              width: max(1, proxy.size.width - border * 2),
              height: max(1, proxy.size.height - border - captionHeight)
            )
            .clipped()
            .padding(.top, border)

          if let caption = cleanText(element.text), !caption.isEmpty {
            Text(caption)
              .font(canvasFont(element.style, fallbackSize: 46, handwritten: true))
              .foregroundStyle(canvasColor(element.style.colorHex, fallback: .black).opacity(0.88))
              .lineLimit(2)
              .multilineTextAlignment(.leading)
              .frame(maxWidth: .infinity, maxHeight: captionHeight, alignment: .leading)
              .padding(.horizontal, border)
              .frame(maxHeight: .infinity, alignment: .bottom)
              .clipped()
          }

          CaptroPhotoPrintFinish(seed: element.id)
            .padding(border)
            .padding(.bottom, max(0, captionHeight - border))
        }
        .captroMaterialShadow(elevation(for: element), seed: element.id)
      }
    } else {
      Group {
        if element.style.shapeName == "cutout" || canvas.template == .importedArtwork {
          mediaImage(element)
        } else {
          mediaImage(element)
            .overlay { CaptroPhotoPrintFinish(seed: element.id) }
        }
      }
        .clipShape(MIRANotePhotoMaskShape(
          name: element.style.shapeName,
          seed: element.id,
          cornerRadius: CGFloat(max(0, element.style.cornerRadius ?? 3))
        ))
        .overlay {
          MIRANotePhotoMaskShape(
            name: element.style.shapeName,
            seed: element.id,
            cornerRadius: CGFloat(max(0, element.style.cornerRadius ?? 3))
          )
            .stroke(
              canvasColor(element.style.borderColorHex, fallback: .white).opacity(element.style.borderWidth == nil ? 0 : 0.55),
              lineWidth: CGFloat(element.style.borderWidth ?? 0)
            )
        }
        .captroMaterialShadow(
          element.style.material == "full_bleed" ? .flush : elevation(for: element),
          seed: element.id
        )
    }
  }

  @ViewBuilder
  private func mediaImage(_ element: MIRANoteCanvasElement) -> some View {
    GeometryReader { proxy in
      let localImage = element.mediaAssetId.flatMap { localImages[$0] } ?? localImages[element.id]
      let contentMode: ContentMode = element.style.blendMode == "fit" ? .fit : .fill
      let zoom = CGFloat(max(1, element.cropScale))
      let normalizedCropX = CGFloat(min(1, max(0, element.cropX)))
      let normalizedCropY = CGFloat(min(1, max(0, element.cropY)))
      let horizontalTravel = proxy.size.width * (zoom - 1) * 0.5
      let verticalTravel = proxy.size.height * (zoom - 1) * 0.5
      let cropOffset = CGSize(
        width: (0.5 - normalizedCropX) * 2 * horizontalTravel,
        height: (0.5 - normalizedCropY) * 2 * verticalTravel
      )

      Group {
        if let localImage {
          Image(uiImage: localImage)
            .resizable()
            .aspectRatio(contentMode: contentMode)
        } else if let asset = CaptroNoteAsset.resolve(element.mediaAssetId) {
          CaptroNoteAssetView(asset: asset, contentMode: contentMode)
        } else {
          MIRACachedImage(
            url: cleanText(element.mediaUrl),
            fallbackURLs: [element.thumbnailUrl].compactMap { cleanText($0) },
            maxPixelSize: mode == .wallPreview ? 960 : 1800,
            animatesNetworkLoad: mode != .wallPreview,
            keepsPreviousImageWhileLoading: true
          ) { image in
            image.resizable().aspectRatio(contentMode: contentMode)
          } placeholder: {
            CaptroPhotographedPaper(
              seed: "photo-placeholder-\(element.id)",
              kind: .photographic,
              base: Color(red: 0.79, green: 0.78, blue: 0.73),
              textureOpacity: 0.20,
              directionalLight: 0.12
            )
            .overlay {
              Image(systemName: "photo")
                .font(.system(size: max(28, proxy.size.width * 0.12), weight: .light))
                .foregroundStyle(Color.black.opacity(0.22))
            }
          }
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .scaleEffect(zoom)
      .offset(cropOffset)
      .frame(width: proxy.size.width, height: proxy.size.height)
      .clipped()
    }
  }

  private func textElement(_ element: MIRANoteCanvasElement) -> some View {
    let metrics = MIRANoteTextMetrics.decode(element.style.shapeName)
    return Text(cleanText(element.text) ?? "")
      .font(
        canvasFont(
          element.style,
          fallbackSize: element.kind == .handwrittenCaption ? 48 : 58,
          handwritten: element.kind == .handwrittenCaption
        )
      )
      .fontWeight(fontWeight(element.style.fontWeight))
      .foregroundStyle(canvasColor(element.style.colorHex, fallback: textFallback))
      .multilineTextAlignment(textAlignment(element.style.textAlignment))
      .tracking(metrics.tracking)
      .lineSpacing(metrics.lineSpacing)
      .lineLimit(nil)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment(element.style.textAlignment))
      .padding(6)
      .allowsTightening(false)
      .clipped()
  }

  @ViewBuilder
  private func paperElement(_ element: MIRANoteCanvasElement, torn: Bool) -> some View {
    let shape = MIRANoteTornPaperShape(seed: element.id, torn: torn)
    if let asset = CaptroNoteAsset.resolve(element.style.material) {
      CaptroNoteAssetView(asset: asset, contentMode: .fill)
        .clipShape(shape)
        .captroMaterialShadow(elevation(for: element), seed: element.id)
    } else {
      CaptroPhotographedPaper(
        seed: element.id,
        kind: paperKind(element.style.material ?? "cotton_paper"),
        base: canvasColor(element.style.colorHex, fallback: Color(red: 0.94, green: 0.91, blue: 0.82)),
        textureOpacity: 0.42 * mode.textureDetail,
        directionalLight: 0.18
      )
      .clipShape(shape)
      .overlay {
        shape.stroke(Color.black.opacity(0.055), lineWidth: 1.5)
      }
      .captroMaterialShadow(elevation(for: element), seed: element.id)
    }
  }

  @ViewBuilder
  private func stickerElement(_ element: MIRANoteCanvasElement) -> some View {
    let color = canvasColor(
      element.style.colorHex,
      fallback: Color(red: 0.78, green: 0.25, blue: 0.32)
    )
    if let asset = CaptroNoteAsset.resolve(element.style.stickerName) {
      CaptroNoteAssetView(asset: asset)
    } else {
      switch element.style.stickerName?.lowercased() {
      case "paperclip":
        MIRANotePaperclip(seed: element.id)
      case "pushpin", "push_pin", "pin":
        MIRANotePushPin(seed: element.id, color: color)
      case "ticket":
        MIRANoteTicket(seed: element.id, color: color)
      case "cassette":
        MIRANoteCassette(seed: element.id, color: color)
      case "television", "tv":
        MIRANoteTelevision(seed: element.id, color: color)
      case "polaroidframe", "polaroid_frame":
        MIRANoteEmptyPolaroid(seed: element.id)
      case "passportstamp", "passport_stamp":
        MIRANotePassportStamp(seed: element.id, color: color)
      case "coffeestain", "coffee_stain":
        MIRANoteCoffeeStain(seed: element.id, color: color)
      case "qrcode", "qr_code":
        MIRANoteQRCodeView(value: cleanText(element.text) ?? "https://captro.app")
          .padding(6)
          .background(
            CaptroPhotographedPaper(
              seed: "qr-\(element.id)",
              kind: .photographic,
              base: .white,
              textureOpacity: 0.12,
              directionalLight: 0.08
            )
          )
          .captroMaterialShadow(.taped, seed: element.id)
      default:
        Image(systemName: stickerSymbol(element.style.stickerName))
          .resizable()
          .scaledToFit()
          .symbolRenderingMode(.palette)
          .foregroundStyle(color, Color.white.opacity(0.86))
          .padding(10)
          .captroMaterialShadow(.taped, seed: element.id)
      }
    }
  }

  @ViewBuilder
  private func flowerElement(_ element: MIRANoteCanvasElement) -> some View {
    if let asset = CaptroNoteAsset.resolve(element.style.material) {
      CaptroNoteAssetView(asset: asset)
    } else {
      MIRANotePressedFlower(
        seed: element.id,
        color: canvasColor(
          element.style.colorHex,
          fallback: Color(red: 0.77, green: 0.39, blue: 0.43)
        )
      )
    }
  }

  private func drawingElement(_ element: MIRANoteCanvasElement) -> some View {
    let drawingName = element.style.drawingName?.lowercased() ?? "scribble"
    let strokeColor = canvasColor(element.style.colorHex, fallback: .black).opacity(0.82)

    return Canvas { context, size in
      var path = Path()
      switch drawingName {
      case "hand_drawn_arrow", "arrow":
        path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.72))
        path.addCurve(
          to: CGPoint(x: size.width * 0.82, y: size.height * 0.30),
          control1: CGPoint(x: size.width * 0.30, y: size.height * 0.92),
          control2: CGPoint(x: size.width * 0.55, y: size.height * 0.08)
        )
        path.move(to: CGPoint(x: size.width * 0.62, y: size.height * 0.24))
        path.addLine(to: CGPoint(x: size.width * 0.84, y: size.height * 0.29))
        path.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * 0.51))
      case "underline":
        path.move(to: CGPoint(x: size.width * 0.06, y: size.height * 0.60))
        path.addCurve(
          to: CGPoint(x: size.width * 0.94, y: size.height * 0.54),
          control1: CGPoint(x: size.width * 0.32, y: size.height * 0.42),
          control2: CGPoint(x: size.width * 0.68, y: size.height * 0.72)
        )
      default:
        path.move(to: CGPoint(x: size.width * 0.08, y: size.height * 0.64))
        path.addCurve(
          to: CGPoint(x: size.width * 0.88, y: size.height * 0.34),
          control1: CGPoint(x: size.width * 0.31, y: size.height * 0.06),
          control2: CGPoint(x: size.width * 0.60, y: size.height * 0.92)
        )
      }
      context.stroke(
        path,
        with: .color(strokeColor),
        style: StrokeStyle(lineWidth: max(4, size.width * 0.025), lineCap: .round, lineJoin: .round)
      )
    }
  }

  @ViewBuilder
  private func shapeElement(_ element: MIRANoteCanvasElement) -> some View {
    let color = canvasColor(element.style.colorHex, fallback: Color(red: 0.84, green: 0.74, blue: 0.48))
    switch element.style.shapeName?.lowercased() {
    case "circle":
      Circle().fill(color)
    case "capsule":
      Capsule().fill(color)
    case "star":
      Image(systemName: "star.fill").resizable().scaledToFit().foregroundStyle(color)
    default:
      RoundedRectangle(cornerRadius: CGFloat(max(0, element.style.cornerRadius ?? 12))).fill(color)
    }
  }

  private var backgroundFallback: Color {
    canvas.template == .darkAlbum
      ? Color(red: 0.075, green: 0.07, blue: 0.065)
      : Color(red: 0.95, green: 0.925, blue: 0.86)
  }

  private var textFallback: Color {
    canvas.template == .darkAlbum ? .white : Color(red: 0.09, green: 0.075, blue: 0.06)
  }

  private func paperKind(_ material: String) -> CaptroPaperKind {
    switch material.lowercased() {
    case "linen", "fabric": return .linen
    case "photo", "photographic", "polaroid": return .photographic
    case "kraft", "cardstock": return .kraft
    case "notebook", "notebook_paper", "lined": return .notebook
    case "graph", "graph_paper": return .graph
    default: return .archival
    }
  }

  private func elevation(for element: MIRANoteCanvasElement) -> CaptroMaterialElevation {
    if (element.style.shadowLevel ?? 0) >= 4 { return .lifted }
    switch element.kind {
    case .photo, .polaroid: return .photograph
    case .tape: return .taped
    case .sticker, .flower: return .pinned
    case .tornPaper, .texturedPaper: return .taped
    default: return .flush
    }
  }

  private func canvasFont(
    _ style: MIRANoteCanvasElementStyle,
    fallbackSize: CGFloat,
    handwritten: Bool
  ) -> Font {
    let size = max(18, CGFloat(style.fontSize ?? Double(fallbackSize)))
    let name = style.fontName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !name.isEmpty { return .custom(name, size: size) }
    return handwritten
      ? .system(size: size, weight: .regular, design: .rounded)
      : .system(size: size, weight: .regular, design: .serif)
  }

  private func fontWeight(_ value: String?) -> Font.Weight {
    switch value?.lowercased() {
    case "black", "heavy": return .black
    case "bold": return .bold
    case "semibold": return .semibold
    case "medium": return .medium
    case "light": return .light
    default: return .regular
    }
  }

  private func textAlignment(_ value: MIRANoteCanvasTextAlignment?) -> TextAlignment {
    switch value {
    case .center: return .center
    case .trailing: return .trailing
    default: return .leading
    }
  }

  private func frameAlignment(_ value: MIRANoteCanvasTextAlignment?) -> Alignment {
    switch value {
    case .center: return .center
    case .trailing: return .trailing
    default: return .leading
    }
  }

  private func stickerSymbol(_ value: String?) -> String {
    switch value?.lowercased() {
    case "airplane", "travel": return "airplane"
    case "coffee": return "cup.and.saucer.fill"
    case "music": return "music.note"
    case "camera": return "camera.fill"
    case "leaf": return "leaf.fill"
    case "sparkle": return "sparkles"
    default: return "heart.fill"
    }
  }

  private func accessibilityLabel(for element: MIRANoteCanvasElement) -> String {
    if let text = cleanText(element.text), !text.isEmpty { return text }
    switch element.kind {
    case .photo, .polaroid: return "Photo"
    case .tape: return "Decorative tape"
    case .flower: return "Flower decoration"
    case .sticker: return "Sticker"
    default: return "Note decoration"
    }
  }

  private func cleanText(_ value: String?) -> String? {
    guard let value else { return nil }
    let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.isEmpty ? nil : clean
  }

  private func canvasColor(_ value: String?, fallback: Color) -> Color {
    guard let value else { return fallback }
    let token = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let tokenColors: [String: Color] = [
      "butter": Color(red: 0.96, green: 0.86, blue: 0.49),
      "blush": Color(red: 0.94, green: 0.68, blue: 0.72),
      "sky": Color(red: 0.69, green: 0.84, blue: 0.89),
      "mint": Color(red: 0.72, green: 0.84, blue: 0.68),
      "cream": Color(red: 0.96, green: 0.93, blue: 0.84),
      "paper": Color(red: 0.95, green: 0.93, blue: 0.87),
      "black": .black,
      "white": .white,
    ]
    if let color = tokenColors[token] { return color }

    let hex = token.replacingOccurrences(of: "#", with: "")
    guard hex.count == 6 || hex.count == 8, let number = UInt64(hex, radix: 16) else { return fallback }
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
    if hex.count == 8 {
      red = Double((number >> 24) & 0xFF) / 255
      green = Double((number >> 16) & 0xFF) / 255
      blue = Double((number >> 8) & 0xFF) / 255
      alpha = Double(number & 0xFF) / 255
    } else {
      red = Double((number >> 16) & 0xFF) / 255
      green = Double((number >> 8) & 0xFF) / 255
      blue = Double(number & 0xFF) / 255
      alpha = 1
    }
    return Color(red: red, green: green, blue: blue, opacity: alpha)
  }
}

private struct MIRANotePaperclip: View {
  let seed: String

  var body: some View {
    GeometryReader { proxy in
      let line = max(2.2, min(proxy.size.width, proxy.size.height) * 0.075)
      ZStack {
        RoundedRectangle(cornerRadius: min(proxy.size.width, proxy.size.height) * 0.28)
          .trim(from: 0.04, to: 0.94)
          .stroke(
            LinearGradient(
              colors: [Color.white, Color(red: 0.37, green: 0.38, blue: 0.39), Color.white.opacity(0.92)],
              startPoint: .leading,
              endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
          )
          .padding(line)

        RoundedRectangle(cornerRadius: min(proxy.size.width, proxy.size.height) * 0.18)
          .trim(from: 0.12, to: 0.90)
          .stroke(Color.white.opacity(0.70), style: StrokeStyle(lineWidth: max(1, line * 0.38), lineCap: .round))
          .padding(line * 2.2)
      }
      .rotationEffect(.degrees(CaptroPhysicalSeed.rotation(seed, salt: 901, range: -8...7)))
    }
    .captroMaterialShadow(.pinned, seed: seed)
  }
}

private struct MIRANotePushPin: View {
  let seed: String
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let diameter = min(proxy.size.width, proxy.size.height) * 0.62
      ZStack(alignment: .top) {
        Capsule()
          .fill(
            LinearGradient(
              colors: [Color.white.opacity(0.78), Color(red: 0.28, green: 0.27, blue: 0.25)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
          .frame(width: max(2, diameter * 0.09), height: proxy.size.height * 0.48)
          .offset(y: proxy.size.height * 0.39)

        Circle()
          .fill(
            RadialGradient(
              colors: [Color.white.opacity(0.78), color, color.opacity(0.72)],
              center: .topLeading,
              startRadius: 1,
              endRadius: diameter * 0.62
            )
          )
          .frame(width: diameter, height: diameter)
          .overlay {
            Circle().stroke(Color.black.opacity(0.18), lineWidth: max(0.8, diameter * 0.018))
          }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
    .captroMaterialShadow(.pinned, seed: seed)
  }
}

private struct MIRANoteTicket: View {
  let seed: String
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let notch = max(5, proxy.size.height * 0.15)
      ZStack {
        CaptroPhotographedPaper(
          seed: "ticket-\(seed)",
          kind: .kraft,
          base: color,
          textureOpacity: 0.42,
          directionalLight: 0.16
        )

        HStack(spacing: proxy.size.width * 0.07) {
          Image(systemName: "star.fill")
            .font(.system(size: max(12, proxy.size.height * 0.30), weight: .bold))
          VStack(spacing: max(2, proxy.size.height * 0.05)) {
            Rectangle().frame(height: max(1, proxy.size.height * 0.025))
            Rectangle().frame(height: max(1, proxy.size.height * 0.025))
            Rectangle().frame(height: max(1, proxy.size.height * 0.025))
          }
        }
        .foregroundStyle(Color.black.opacity(0.48))
        .padding(.horizontal, proxy.size.width * 0.12)

        HStack {
          Circle().fill(Color.black.opacity(0.12)).frame(width: notch, height: notch).offset(x: -notch * 0.5)
          Spacer()
          Circle().fill(Color.black.opacity(0.12)).frame(width: notch, height: notch).offset(x: notch * 0.5)
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: max(3, proxy.size.height * 0.08)))
      .overlay {
        RoundedRectangle(cornerRadius: max(3, proxy.size.height * 0.08))
          .stroke(Color.black.opacity(0.20), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
      }
    }
    .captroMaterialShadow(.taped, seed: seed)
  }
}

private struct MIRANoteCassette: View {
  let seed: String
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let radius = max(4, proxy.size.height * 0.10)
      ZStack {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(
            LinearGradient(
              colors: [color.opacity(0.95), color.opacity(0.72), Color.black.opacity(0.30)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )

        RoundedRectangle(cornerRadius: radius * 0.45)
          .fill(Color(red: 0.94, green: 0.91, blue: 0.82).opacity(0.86))
          .frame(width: proxy.size.width * 0.72, height: proxy.size.height * 0.46)

        HStack(spacing: proxy.size.width * 0.15) {
          ForEach(0..<2, id: \.self) { _ in
            Circle()
              .fill(Color.black.opacity(0.62))
              .overlay { Circle().stroke(Color.white.opacity(0.54), lineWidth: 2) }
          }
        }
        .frame(width: proxy.size.width * 0.44, height: proxy.size.height * 0.23)

        Capsule()
          .fill(Color.black.opacity(0.68))
          .frame(width: proxy.size.width * 0.45, height: proxy.size.height * 0.075)
          .offset(y: proxy.size.height * 0.34)
      }
      .overlay { RoundedRectangle(cornerRadius: radius).stroke(Color.black.opacity(0.32), lineWidth: 1.4) }
    }
    .captroMaterialShadow(.pinned, seed: seed)
  }
}

private struct MIRANoteTelevision: View {
  let seed: String
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let radius = max(6, proxy.size.height * 0.13)
      ZStack {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
          .fill(
            LinearGradient(
              colors: [color.opacity(0.92), color.opacity(0.62), Color.black.opacity(0.42)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            )
          )

        RoundedRectangle(cornerRadius: radius * 0.78, style: .continuous)
          .fill(
            RadialGradient(
              colors: [Color(red: 0.24, green: 0.31, blue: 0.29), Color.black.opacity(0.88)],
              center: .center,
              startRadius: 2,
              endRadius: proxy.size.width * 0.40
            )
          )
          .frame(width: proxy.size.width * 0.77, height: proxy.size.height * 0.72)
          .offset(x: -proxy.size.width * 0.055)
          .overlay {
            LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .center)
              .clipShape(RoundedRectangle(cornerRadius: radius * 0.78))
              .frame(width: proxy.size.width * 0.77, height: proxy.size.height * 0.72)
              .offset(x: -proxy.size.width * 0.055)
          }

        VStack(spacing: proxy.size.height * 0.08) {
          Circle().fill(Color.white.opacity(0.35))
          Circle().fill(Color.white.opacity(0.22))
        }
        .frame(width: proxy.size.width * 0.075)
        .offset(x: proxy.size.width * 0.40)
      }
      .overlay { RoundedRectangle(cornerRadius: radius).stroke(Color.black.opacity(0.35), lineWidth: 1.5) }
    }
    .captroMaterialShadow(.photograph, seed: seed)
  }
}

private struct MIRANoteEmptyPolaroid: View {
  let seed: String

  var body: some View {
    GeometryReader { proxy in
      let border = max(8, proxy.size.width * 0.07)
      CaptroPhotographedPaper(
        seed: "empty-polaroid-\(seed)",
        kind: .photographic,
        base: Color(red: 0.98, green: 0.97, blue: 0.93),
        textureOpacity: 0.18,
        directionalLight: 0.12
      )
      .overlay(alignment: .top) {
        CaptroPhotographedPaper(
          seed: "empty-polaroid-image-\(seed)",
          kind: .photographic,
          base: Color(red: 0.70, green: 0.71, blue: 0.68),
          textureOpacity: 0.22,
          directionalLight: 0.14
        )
        .padding(.horizontal, border)
        .padding(.top, border)
        .padding(.bottom, proxy.size.height * 0.24)
      }
    }
    .captroMaterialShadow(.photograph, seed: seed)
  }
}

private struct MIRANotePassportStamp: View {
  let seed: String
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let line = max(1.2, min(proxy.size.width, proxy.size.height) * 0.025)
      ZStack {
        Circle().stroke(color.opacity(0.82), lineWidth: line)
        Circle()
          .stroke(color.opacity(0.65), style: StrokeStyle(lineWidth: max(0.8, line * 0.55), dash: [7, 5]))
          .padding(min(proxy.size.width, proxy.size.height) * 0.10)
        Image(systemName: "airplane")
          .font(.system(size: max(12, min(proxy.size.width, proxy.size.height) * 0.28), weight: .bold))
          .foregroundStyle(color.opacity(0.82))
      }
    }
    .opacity(0.80)
    .blendMode(.multiply)
  }
}

private struct MIRANoteCoffeeStain: View {
  let seed: String
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let line = max(2, min(proxy.size.width, proxy.size.height) * 0.045)
      ZStack {
        Circle()
          .stroke(color.opacity(0.43), lineWidth: line)
          .padding(line)
        Circle()
          .trim(from: 0.08, to: 0.78)
          .stroke(color.opacity(0.24), style: StrokeStyle(lineWidth: line * 0.48, lineCap: .round))
          .padding(line * 2.1)
          .rotationEffect(.degrees(CaptroPhysicalSeed.rotation(seed, salt: 943, range: -18...14)))
        ForEach(0..<5, id: \.self) { index in
          Circle()
            .fill(color.opacity(0.16))
            .frame(width: line * 0.85, height: line * 0.85)
            .offset(
              x: CaptroPhysicalSeed.signed(seed, salt: 951 + index) * proxy.size.width * 0.42,
              y: CaptroPhysicalSeed.signed(seed, salt: 961 + index) * proxy.size.height * 0.42
            )
        }
      }
      .blur(radius: max(0.25, line * 0.07))
    }
    .blendMode(.multiply)
  }
}

private struct MIRANotePressedFlower: View {
  let seed: String
  let color: Color

  var body: some View {
    GeometryReader { proxy in
      let flowerSize = min(proxy.size.width, proxy.size.height) * 0.52
      ZStack {
        Canvas { context, size in
          var stem = Path()
          stem.move(to: CGPoint(x: size.width * 0.52, y: size.height * 0.42))
          stem.addCurve(
            to: CGPoint(x: size.width * 0.44, y: size.height * 0.97),
            control1: CGPoint(x: size.width * 0.57, y: size.height * 0.62),
            control2: CGPoint(x: size.width * 0.40, y: size.height * 0.78)
          )
          context.stroke(stem, with: .color(Color(red: 0.28, green: 0.39, blue: 0.18).opacity(0.72)), lineWidth: max(2, size.width * 0.022))
        }

        ForEach(0..<7, id: \.self) { index in
          Capsule()
            .fill(
              LinearGradient(
                colors: [color.opacity(0.48), color.opacity(0.90), Color.black.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
            .frame(width: flowerSize * 0.32, height: flowerSize * 0.70)
            .offset(y: -flowerSize * 0.28)
            .rotationEffect(.degrees(Double(index) * (360 / 7)))
        }

        Circle()
          .fill(
            RadialGradient(
              colors: [Color(red: 0.88, green: 0.70, blue: 0.24), Color(red: 0.48, green: 0.30, blue: 0.12)],
              center: .topLeading,
              startRadius: 1,
              endRadius: flowerSize * 0.22
            )
          )
          .frame(width: flowerSize * 0.35, height: flowerSize * 0.35)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .opacity(0.84)
      .saturation(0.72)
    }
    .captroMaterialShadow(.taped, seed: seed)
  }
}

private struct MIRANoteQRCodeView: View {
  let value: String

  var body: some View {
    GeometryReader { proxy in
      if let image = MIRANoteQRCodeGenerator.image(value) {
        Image(uiImage: image)
          .resizable()
          .interpolation(.none)
          .scaledToFit()
          .frame(width: proxy.size.width, height: proxy.size.height)
      } else {
        Image(systemName: "qrcode")
          .resizable()
          .scaledToFit()
          .foregroundStyle(.black)
      }
    }
  }
}

private enum MIRANoteQRCodeGenerator {
  static func image(_ value: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(value.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage else { return nil }
    let transformed = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else { return nil }
    return UIImage(cgImage: cgImage)
  }
}

private struct MIRANoteTextMetrics {
  let tracking: CGFloat
  let lineSpacing: CGFloat

  static func decode(_ token: String?) -> Self {
    guard let token, token.hasPrefix("text:") else {
      return Self(tracking: 0, lineSpacing: 4)
    }
    let values = token.dropFirst(5).split(separator: ",").reduce(into: [String: CGFloat]()) { result, pair in
      let parts = pair.split(separator: "=", maxSplits: 1)
      guard parts.count == 2, let value = Double(parts[1]) else { return }
      result[String(parts[0])] = CGFloat(value)
    }
    return Self(
      tracking: min(24, max(-2, values["ls"] ?? 0)),
      lineSpacing: min(40, max(0, values["lh"] ?? 4))
    )
  }
}

private struct MIRANotePhotoMaskShape: Shape {
  let name: String?
  let seed: String
  let cornerRadius: CGFloat

  func path(in rect: CGRect) -> Path {
    switch name?.lowercased() {
    case "circle", "oval":
      return Path(ellipseIn: rect)
    case "arch":
      let radius = min(rect.width * 0.48, rect.height * 0.24)
      return Path(
        UIBezierPath(
          roundedRect: rect,
          byRoundingCorners: [.topLeft, .topRight],
          cornerRadii: CGSize(width: radius, height: radius)
        ).cgPath
      )
    case "torn", "torn_photo":
      return MIRANoteTornPaperShape(seed: seed, torn: true).path(in: rect)
    case "cutout":
      var path = Path()
      path.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.02))
      path.addCurve(
        to: CGPoint(x: rect.maxX - rect.width * 0.04, y: rect.minY + rect.height * 0.26),
        control1: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.02),
        control2: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.06)
      )
      path.addCurve(
        to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.maxY - rect.height * 0.04),
        control1: CGPoint(x: rect.maxX, y: rect.midY),
        control2: CGPoint(x: rect.maxX, y: rect.maxY)
      )
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.maxY - rect.height * 0.16),
        control1: CGPoint(x: rect.midX, y: rect.maxY),
        control2: CGPoint(x: rect.minX, y: rect.maxY)
      )
      path.addCurve(
        to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.02),
        control1: CGPoint(x: rect.minX, y: rect.midY),
        control2: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.10)
      )
      path.closeSubpath()
      return path
    case "soft", "rounded":
      return RoundedRectangle(cornerRadius: max(18, cornerRadius), style: .continuous).path(in: rect)
    default:
      return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
    }
  }
}

private struct MIRANoteTornPaperShape: Shape {
  let seed: String
  let torn: Bool

  func path(in rect: CGRect) -> Path {
    guard torn else {
      return Path { path in
        path.addRect(rect)
      }
    }
    let teeth = 18
    var path = Path()
    path.move(to: CGPoint(x: 1, y: 3))
    for index in 0...teeth {
      let x = rect.width * CGFloat(index) / CGFloat(teeth)
      let y = 1 + CaptroPhysicalSeed.unit(seed, salt: 701 + index) * 6
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in 0...teeth {
      let y = rect.height * CGFloat(index) / CGFloat(teeth)
      let x = rect.width - 1 - CaptroPhysicalSeed.unit(seed, salt: 751 + index) * 5
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in stride(from: teeth, through: 0, by: -1) {
      let x = rect.width * CGFloat(index) / CGFloat(teeth)
      let y = rect.height - 1 - CaptroPhysicalSeed.unit(seed, salt: 801 + index) * 6
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in stride(from: teeth, through: 0, by: -1) {
      let y = rect.height * CGFloat(index) / CGFloat(teeth)
      let x = 1 + CaptroPhysicalSeed.unit(seed, salt: 851 + index) * 5
      path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
  }
}
