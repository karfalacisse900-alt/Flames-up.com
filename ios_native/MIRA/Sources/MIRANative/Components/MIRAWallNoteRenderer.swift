import SwiftUI
import UIKit

struct MIRAWallNoteTile: View {
  let note: MIRAWallNote
  let isNew: Bool
  let wallScale: CGFloat
  let isLifted: Bool
  let isPressed: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasEntered = false

  private var presentation: MIRAWallNotePresentation {
    MIRAWallNotePresentationResolver.resolve(note)
  }

  var body: some View {
    MIRAWallNoteRenderer(note: note, zoom: 1, isFocused: isLifted, wallScale: wallScale)
      .opacity(hasEntered ? 1 : initialOpacity)
      .scaleEffect(
        x: hasEntered ? 1 : initialScale.width,
        y: hasEntered ? 1 : initialScale.height,
        anchor: entranceAnchor
      )
      .offset(hasEntered ? .zero : initialOffset)
      .rotationEffect(.degrees(hasEntered ? 0 : initialEntranceRotation))
      .rotation3DEffect(
        .degrees(isLifted ? 0 : warpX),
        axis: (x: 1, y: 0, z: 0),
        anchor: warpAnchor,
        perspective: 0.22
      )
      .rotation3DEffect(
        .degrees(isLifted ? 0 : warpY),
        axis: (x: 0, y: 1, z: 0),
        anchor: warpAnchor,
        perspective: 0.22
      )
      .scaleEffect(interactionScale)
      .offset(x: isLifted ? -1.5 : 0, y: isLifted ? -8 : 0)
      .animation(CaptroMotion.buttonPressAnimation(reduceMotion: reduceMotion), value: isPressed)
      .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isLifted)
      .onAppear {
        guard !hasEntered else { return }
        if reduceMotion || !isNew {
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

  private var interactionScale: CGFloat {
    if isPressed { return 0.985 }
    return isLifted ? 1.045 : 1
  }

  private var warpX: Double {
    switch presentation.warp {
    case .topLeftLifted: -0.42
    case .bottomRightLifted: 0.46
    case .curledBottom: 0.72
    case .centerBend: 0.18
    case .flat: 0
    }
  }

  private var warpY: Double {
    switch presentation.warp {
    case .topLeftLifted: 0.48
    case .bottomRightLifted: -0.44
    case .centerBend: -0.20
    case .curledBottom, .flat: 0
    }
  }

  private var warpAnchor: UnitPoint {
    switch presentation.warp {
    case .topLeftLifted: .bottomTrailing
    case .bottomRightLifted: .topLeading
    case .curledBottom: .top
    case .centerBend, .flat: .center
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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let note: MIRAWallNote
  let zoom: CGFloat
  let isFocused: Bool
  var localMediaImage: UIImage? = nil
  var wallScale: CGFloat = 1

  private var presentation: MIRAWallNotePresentation {
    MIRAWallNotePresentationResolver.resolve(note, hasLocalMedia: localMediaImage != nil)
  }

  private var renderDetail: MIRAWallNoteRenderDetail {
    MIRAWallNotePresentationResolver.renderDetail(forWallScale: wallScale, isFocused: isFocused)
  }

  private var mediaURL: String? {
    [note.mediaThumbnailUrl, note.mediaUrl]
      .compactMap { value in
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? nil : clean
      }
      .first
  }

  private var hasMedia: Bool {
    localMediaImage != nil || mediaURL != nil
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        MIRAWallPaperBackground(note: note, presentation: presentation, renderDetail: renderDetail)

        if note.isVoiceNote {
          MIRAWallVoiceNoteContent(note: note, presentation: presentation)
        } else if hasMedia {
          MIRAWallPhotoNoteContent(
            note: note,
            presentation: presentation,
            mediaURL: mediaURL,
            localImage: localMediaImage,
            zoom: zoom,
            wallScale: wallScale
          )
        } else {
          MIRAWallTypographyView(
            note: note,
            presentation: presentation,
            zoom: zoom,
            wallScale: wallScale,
            isFocused: isFocused
          )
        }

        MIRAWallWarpCue(warp: presentation.warp, darkPaper: presentation.usesDarkPaper)
          .opacity(renderDetail == .distant ? 0.54 : 1)
          .transition(.opacity)

        if renderDetail == .distant {
          MIRAWallDistantAttachmentCue(
            attachment: presentation.attachment,
            darkPaper: presentation.usesDarkPaper
          )
        } else {
          MIRAWallPhysicalDetails(note: note, presentation: presentation, zoom: zoom)
            .transition(.opacity)
        }

        if renderDetail == .full, zoom >= 0.74 {
          MIRAWallIdentityMark(note: note, style: presentation.style, zoom: zoom)
            .transition(.opacity)
        }

        if renderDetail != .distant {
          MIRAWallLivingNoteMarks(note: note, presentation: presentation)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
      .contentShape(Rectangle())
      .animation(CaptroMotion.mediaFadeAnimation(reduceMotion: reduceMotion), value: renderDetail)
      .shadow(
        color: .black.opacity(isFocused ? 0.18 : depth.contactOpacity),
        radius: isFocused ? 2.8 : depth.contactRadius,
        x: isFocused ? 1.2 : depth.contactX,
        y: isFocused ? 3.2 : depth.contactY
      )
      .shadow(
        color: .black.opacity(isFocused ? 0.25 : depth.castOpacity),
        radius: isFocused ? 20 : depth.castRadius,
        x: isFocused ? 6 : depth.castX,
        y: isFocused ? 15 : depth.castY
      )
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(note.isGhost ? "Anonymous note" : "Note by \(note.authorPreview?.title ?? "Captro member")")
    .accessibilityValue(note.body)
  }

  private var depth: MIRAWallDepthProfile {
    MIRAWallDepthProfile.resolve(
      style: presentation.style,
      warp: presentation.warp,
      zoom: zoom
    )
  }
}

private struct MIRAWallVoiceNoteContent: View {
  let note: MIRAWallNote
  let presentation: MIRAWallNotePresentation

  var body: some View {
    GeometryReader { proxy in
      let ink = presentation.usesDarkPaper ? Color.white : Color.black
      VStack(alignment: .leading, spacing: max(6, proxy.size.height * 0.045)) {
        HStack(spacing: 7) {
          Image(systemName: "waveform")
            .font(.system(size: max(11, proxy.size.width * 0.075), weight: .bold))
          Text("VOICE NOTE")
            .font(.system(size: max(9, proxy.size.width * 0.054), weight: .black, design: .monospaced))
            .tracking(0.6)
          Spacer(minLength: 2)
          Text(durationLabel)
            .font(.system(size: max(8, proxy.size.width * 0.048), weight: .bold, design: .monospaced))
        }

        HStack(spacing: 9) {
          Image(systemName: "play.fill")
            .font(.system(size: max(11, proxy.size.width * 0.065), weight: .bold))
            .frame(width: max(30, proxy.size.width * 0.19), height: max(30, proxy.size.width * 0.19))
            .background(ink.opacity(0.10), in: Circle())

          MIRAWallWaveformView(samples: note.voice?.waveform ?? [], tint: ink)
            .frame(height: max(28, proxy.size.height * 0.22))
        }

        if !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text(note.body)
            .font(.system(size: max(10, min(18, proxy.size.width * 0.066)), weight: .semibold, design: .serif))
            .lineLimit(3)
            .minimumScaleFactor(0.76)
            .multilineTextAlignment(.leading)
        }
      }
      .foregroundStyle(ink.opacity(0.88))
      .padding(.horizontal, max(13, proxy.size.width * 0.075))
      .padding(.vertical, max(14, proxy.size.height * 0.09))
    }
    .allowsHitTesting(false)
  }

  private var durationLabel: String {
    let seconds = max(0, Int((note.voice?.durationSeconds ?? 0).rounded(.down)))
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
  }
}

private struct MIRAWallLivingNoteMarks: View {
  let note: MIRAWallNote
  let presentation: MIRAWallNotePresentation

  var body: some View {
    GeometryReader { proxy in
      let ink = presentation.usesDarkPaper ? Color.white : Color.black
      ZStack {
        if note.canFlip {
          Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: max(8, proxy.size.width * 0.052), weight: .bold))
            .foregroundStyle(ink.opacity(0.54))
            .padding(max(7, proxy.size.width * 0.045))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }

        if note.resolvedSignatureCount > 0 {
          Label("\(note.resolvedSignatureCount)", systemImage: "pencil.line")
            .font(.system(size: max(7, proxy.size.width * 0.044), weight: .bold, design: .rounded))
            .foregroundStyle(ink.opacity(0.58))
            .padding(max(7, proxy.size.width * 0.045))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private enum MIRAWallLight {
  static let contactX: CGFloat = 0.7
  static let contactY: CGFloat = 1.4
  static let castX: CGFloat = 2.6
  static let castY: CGFloat = 4.8
}

private struct MIRAWallDepthProfile {
  let contactOpacity: Double
  let contactRadius: CGFloat
  let contactX: CGFloat
  let contactY: CGFloat
  let castOpacity: Double
  let castRadius: CGFloat
  let castX: CGFloat
  let castY: CGFloat

  static func resolve(
    style: MIRAWallNoteVisualStyle,
    warp: MIRAWallPaperWarp,
    zoom: CGFloat
  ) -> MIRAWallDepthProfile {
    let thickness: CGFloat
    switch style {
    case .polaroid: thickness = 1.55
    case .postcard, .poster: thickness = 1.22
    case .receipt, .minimal: thickness = 0.70
    default: thickness = 1
    }
    let lift: CGFloat = warp == .flat ? 1 : (warp == .curledBottom ? 1.42 : 1.22)
    let scale = max(0.74, zoom)
    return MIRAWallDepthProfile(
      contactOpacity: style == .minimal ? 0.08 : 0.13,
      contactRadius: max(0.7, 1.15 * thickness * scale),
      contactX: MIRAWallLight.contactX * lift,
      contactY: MIRAWallLight.contactY * lift,
      castOpacity: style == .minimal ? 0.055 : 0.12 + Double((thickness - 1) * 0.035),
      castRadius: max(2, 4.4 * thickness * lift * scale),
      castX: MIRAWallLight.castX * lift,
      castY: MIRAWallLight.castY * lift
    )
  }
}

private struct MIRAWallWarpCue: View {
  let warp: MIRAWallPaperWarp
  let darkPaper: Bool

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        switch warp {
        case .topLeftLifted:
          cornerLift(size: proxy.size, alignment: .topLeading, angle: 135)
        case .bottomRightLifted:
          cornerLift(size: proxy.size, alignment: .bottomTrailing, angle: -45)
        case .curledBottom:
          VStack(spacing: 0) {
            Spacer()
            LinearGradient(
              colors: [Color.clear, shadowColor.opacity(0.08), highlightColor.opacity(0.09)],
              startPoint: .top,
              endPoint: .bottom
            )
            .frame(height: min(13, proxy.size.height * 0.08))
          }
        case .centerBend:
          LinearGradient(
            colors: [Color.clear, highlightColor.opacity(0.045), shadowColor.opacity(0.035), Color.clear],
            startPoint: .leading,
            endPoint: .trailing
          )
        case .flat:
          Color.clear
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func cornerLift(size: CGSize, alignment: Alignment, angle: Double) -> some View {
    LinearGradient(
      colors: [highlightColor.opacity(0.13), Color.clear, shadowColor.opacity(0.08)],
      startPoint: .topLeading,
      endPoint: .bottomTrailing
    )
    .frame(width: min(42, size.width * 0.24), height: min(42, size.height * 0.24))
    .rotationEffect(.degrees(angle))
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
  }

  private var shadowColor: Color { darkPaper ? .white : .black }
  private var highlightColor: Color { darkPaper ? .black : .white }
}
private struct MIRAWallDistantAttachmentCue: View {
  let attachment: MIRAWallNoteAttachment
  let darkPaper: Bool

  var body: some View {
    VStack(spacing: 0) {
      cue
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var cue: some View {
    switch attachment {
    case .tape:
      RoundedRectangle(cornerRadius: 1.8, style: .continuous)
        .fill((darkPaper ? Color.white : Color(red: 0.91, green: 0.82, blue: 0.63)).opacity(0.72))
        .frame(width: 54, height: 12)
        .rotationEffect(.degrees(-2.4))
        .offset(y: -5)
        .shadow(color: .black.opacity(0.10), radius: 1.2, y: 1)
    case .pin:
      Circle()
        .fill(Color(red: 0.76, green: 0.17, blue: 0.10))
        .frame(width: 13, height: 13)
        .overlay(alignment: .topLeading) {
          Circle().fill(Color.white.opacity(0.48)).frame(width: 3.4, height: 3.4).padding(2.2)
        }
        .offset(y: -6)
        .shadow(color: .black.opacity(0.20), radius: 1.5, y: 1.5)
    case .paperclip:
      Image(systemName: "paperclip")
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle((darkPaper ? Color.white : Color.black).opacity(0.52))
        .rotationEffect(.degrees(-13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 10)
        .offset(y: -7)
    case .foldedCorner:
      Image(systemName: "triangle.fill")
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle((darkPaper ? Color.white : Color.black).opacity(0.16))
        .rotationEffect(.degrees(45))
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 5)
        .offset(y: -2)
    case .none:
      EmptyView()
    }
  }
}
private struct MIRAWallPaperBackground: View {
  let note: MIRAWallNote
  let presentation: MIRAWallNotePresentation
  let renderDetail: MIRAWallNoteRenderDetail

  @ViewBuilder
  var body: some View {
    switch presentation.style {
    case .sticky:
      MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.48)
        .fill(MIRAWallPaperColor.color(for: presentation.usesAccentColor ? note.colorToken : "cream"))
        .overlay {
          materialLayer.clipShape(MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.48))
        }
    case .editorial:
      MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.42)
        .fill(MIRAWallPaperColor.color(for: "cream"))
        .overlay(alignment: .leading) {
          Rectangle().fill(Color.black.opacity(0.13)).frame(width: 1.5).padding(.vertical, 3)
        }
        .overlay {
          materialLayer.clipShape(MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.42))
        }
    case .handwritten:
      MIRAWallSoftScrapShape(seed: note.id)
        .fill(MIRAWallPaperColor.color(for: presentation.usesAccentColor ? note.colorToken : "paper"))
        .overlay { materialLayer.clipShape(MIRAWallSoftScrapShape(seed: note.id)) }
    case .poster:
      MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.36)
        .fill(presentation.usesDarkPaper
          ? Color(red: 0.075, green: 0.07, blue: 0.06)
          : MIRAWallPaperColor.color(for: presentation.usesAccentColor ? note.colorToken : "paper"))
        .overlay {
          materialLayer.clipShape(MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.36))
        }
        .overlay {
          MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.30)
            .stroke(presentation.usesDarkPaper ? Color.white.opacity(0.20) : Color.black.opacity(0.14), lineWidth: 1)
            .padding(7)
        }
    case .polaroid:
      MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.28)
        .fill(Color(red: 0.968, green: 0.956, blue: 0.915))
        .overlay {
          materialLayer.clipShape(MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.28))
        }
    case .receipt:
      MIRAWallReceiptShape()
        .fill(Color(red: 0.955, green: 0.944, blue: 0.892))
        .overlay { materialLayer.clipShape(MIRAWallReceiptShape()) }
    case .tornPaper:
      MIRAWallTornPaperShape(seed: note.id)
        .fill(presentation.material == .kraft
          ? Color(red: 0.76, green: 0.66, blue: 0.49)
          : MIRAWallPaperColor.color(for: "paper"))
        .overlay { materialLayer.clipShape(MIRAWallTornPaperShape(seed: note.id)) }
    case .notebook:
      MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.38)
        .fill(Color(red: 0.966, green: 0.957, blue: 0.914))
        .overlay {
          materialLayer.clipShape(MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.38))
        }
    case .postcard:
      MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.46)
        .fill(presentation.material == .kraft
          ? Color(red: 0.79, green: 0.69, blue: 0.52)
          : Color(red: 0.90, green: 0.842, blue: 0.716))
        .overlay {
          MIRAWallPostcardMarks()
            .clipShape(MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.46))
        }
        .overlay {
          materialLayer.clipShape(MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.46))
        }
    case .minimal:
      MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.24)
        .fill(Color(red: 0.958, green: 0.937, blue: 0.866).opacity(0.94))
        .overlay {
          materialLayer.clipShape(MIRAWallImperfectPaperShape(seed: note.id, roughness: 0.24))
        }
        .overlay(alignment: .bottomLeading) {
          Rectangle().fill(Color.black.opacity(0.22)).frame(width: 42, height: 1.5)
            .padding(.leading, 18).padding(.bottom, 13)
        }
    }
  }

  private var materialLayer: some View {
    MIRAWallPaperMaterialLayer(
      seed: note.id,
      material: presentation.material,
      darkPaper: presentation.usesDarkPaper,
      detail: renderDetail
    )
  }
}

private struct MIRAWallTypographyView: View {
  let note: MIRAWallNote
  let presentation: MIRAWallNotePresentation
  let zoom: CGFloat
  let wallScale: CGFloat
  let isFocused: Bool

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
    .shadow(color: inkColor.opacity(inkBleedOpacity), radius: inkBleedRadius, x: 0.16, y: 0.12)
    .padding(contentInsets)
    .clipped()
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
      .tracking(inkTracking)
      .multilineTextAlignment(styleAlignment)
      .lineLimit(maxLineCount)
      .minimumScaleFactor(0.68)
      .allowsTightening(false)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
  }

  private func standardTypography(font: Font, alignment: TextAlignment) -> some View {
    Text(note.body)
      .font(font)
      .tracking(inkTracking)
      .multilineTextAlignment(alignment)
      .lineLimit(maxLineCount)
      .minimumScaleFactor(0.68)
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
          .tracking(inkTracking)
          .rotationEffect(.degrees(presentation.typography == .chaos && index == 1 ? -1.4 : 0))
          .offset(
            x: presentation.typography == .thought ? handwritingOffset(index, salt: 1) : 0,
            y: presentation.typography == .thought ? handwritingOffset(index, salt: 2) * 0.45 : 0
          )
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
    return max(9, min(36, base * styleScale * max(0.82, zoom) * 1.08))
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

  private var inkTracking: CGFloat {
    let hash = MIRAWallNotePresentationResolver.stableHash(note.id)
    let variation = CGFloat(Int((hash / 43) % 5) - 2) * 0.035
    switch presentation.typography {
    case .thought, .chaos: return 0.12 + variation
    case .loud: return 0.04 + variation
    case .confession, .editorial: return variation
    }
  }

  private var inkBleedOpacity: Double {
    let distanceBoost = wallScale < 0.72 && !isFocused ? 1.4 : 1
    switch presentation.typography {
    case .loud, .thought: return 0.12 * distanceBoost
    case .chaos: return 0.08 * distanceBoost
    case .confession, .editorial: return 0.045 * distanceBoost
    }
  }

  private var inkBleedRadius: CGFloat {
    switch presentation.typography {
    case .loud: 0.34
    case .thought: 0.24
    case .chaos: 0.18
    case .confession, .editorial: 0.10
    }
  }

  private func handwritingOffset(_ index: Int, salt: Int) -> CGFloat {
    let hash = MIRAWallNotePresentationResolver.stableHash(note.id)
    return (MIRAWallMaterialNoise.unit(hash, 800 + index * 7 + salt) - 0.5) * 1.2
  }
}

private struct MIRAWallPhotoNoteContent: View {
  let note: MIRAWallNote
  let presentation: MIRAWallNotePresentation
  let mediaURL: String?
  let localImage: UIImage?
  let zoom: CGFloat
  let wallScale: CGFloat

  var body: some View {
    GeometryReader { proxy in
      let layout = MIRAWallPhotoNoteLayout.resolve(
        style: presentation.style,
        size: proxy.size,
        textLength: note.body.count
      )
      VStack(alignment: .leading, spacing: layout.spacing) {
        photo
          .frame(maxWidth: .infinity)
          .frame(height: layout.imageHeight)
          .clipped()

        if !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          Text(note.body)
            .font(captionFont)
            .foregroundStyle(inkColor)
            .tracking(presentation.typography == .thought ? 0.10 : 0)
            .multilineTextAlignment(.leading)
            .lineLimit(layout.lineLimit)
            .minimumScaleFactor(0.82)
            .allowsTightening(false)
            .frame(
              maxWidth: .infinity,
              maxHeight: layout.captionHeight,
              alignment: .topLeading
            )
            .clipped()
        }
      }
      .padding(layout.insets)
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
    }
  }

  private var photo: some View {
    Group {
      if let localImage {
        Image(uiImage: localImage)
          .resizable()
          .scaledToFill()
      } else if let mediaURL {
        MIRACachedImage(url: mediaURL, maxPixelSize: mediaDecodeSize) { image in
          image.resizable().scaledToFill()
        } placeholder: {
          photoPlaceholder
        }
      } else {
        photoPlaceholder
      }
    }
    .scaleEffect(1.004)
    .rotationEffect(.degrees(photoCropRotation))
    .clipShape(MIRAWallPhotoCropShape(seed: note.id))
    .overlay {
      MIRAWallPhotoPrintTexture(seed: note.id)
        .clipShape(MIRAWallPhotoCropShape(seed: note.id))
    }
    .overlay {
      MIRAWallPhotoCropShape(seed: note.id)
        .stroke(Color.black.opacity(0.10), lineWidth: 0.65)
    }
  }

  private var photoPlaceholder: some View {
    MIRAWallPaperColor.color(for: note.colorToken)
      .overlay {
        Image(systemName: "photo")
          .font(.system(size: 20, weight: .medium))
          .foregroundStyle(inkColor.opacity(0.24))
      }
  }

  private var captionFont: Font {
    let base: CGFloat
    switch note.body.count {
    case 0...42: base = 24
    case 43...90: base = 21
    case 91...160: base = 18.5
    default: base = 16.5
    }
    let size = max(15, min(30, base * max(0.94, zoom) * 1.08))
    switch presentation.style {
    case .handwritten, .sticky, .notebook, .polaroid:
      return .custom("Noteworthy", size: size)
    case .editorial, .postcard, .minimal:
      return .system(size: size, weight: .medium, design: .serif)
    case .receipt:
      return .system(size: size * 0.94, weight: .medium, design: .monospaced)
    case .poster, .tornPaper:
      return .system(size: size, weight: .semibold, design: .rounded)
    }
  }

  private var inkColor: Color {
    presentation.usesDarkPaper
      ? Color(red: 0.98, green: 0.95, blue: 0.84)
      : Color(red: 0.10, green: 0.095, blue: 0.075)
  }

  private var photoCropRotation: Double {
    let hash = MIRAWallNotePresentationResolver.stableHash(note.id)
    return Double(Int((hash / 31) % 5) - 2) * 0.06
  }

  private var mediaDecodeSize: CGFloat {
    if wallScale < 0.42 { return 280 }
    if wallScale < 0.72 { return 480 }
    return 720
  }
}

private struct MIRAWallPhotoNoteLayout {
  let insets: EdgeInsets
  let spacing: CGFloat
  let imageHeight: CGFloat
  let captionHeight: CGFloat
  let lineLimit: Int

  static func resolve(
    style: MIRAWallNoteVisualStyle,
    size: CGSize,
    textLength: Int
  ) -> MIRAWallPhotoNoteLayout {
    let insets: EdgeInsets
    switch style {
    case .polaroid:
      insets = EdgeInsets(top: 11, leading: 11, bottom: 13, trailing: 11)
    case .receipt:
      insets = EdgeInsets(top: 31, leading: 11, bottom: 30, trailing: 11)
    case .notebook:
      insets = EdgeInsets(top: 25, leading: 29, bottom: 23, trailing: 15)
    case .postcard:
      insets = EdgeInsets(top: 24, leading: 18, bottom: 22, trailing: 18)
    case .poster:
      insets = EdgeInsets(top: 27, leading: 18, bottom: 23, trailing: 18)
    case .minimal:
      insets = EdgeInsets(top: 17, leading: 18, bottom: 29, trailing: 18)
    default:
      insets = EdgeInsets(top: 23, leading: 18, bottom: 22, trailing: 18)
    }

    let hasCaption = textLength > 0
    let spacing: CGFloat = hasCaption ? (style == .receipt ? 5 : 7) : 0
    let availableHeight = max(88, size.height - insets.top - insets.bottom)
    guard hasCaption else {
      return MIRAWallPhotoNoteLayout(
        insets: insets,
        spacing: 0,
        imageHeight: availableHeight,
        captionHeight: 0,
        lineLimit: 0
      )
    }

    let preferredFraction: CGFloat
    if textLength > 160 {
      preferredFraction = 0.62
    } else if textLength > 90 {
      preferredFraction = 0.66
    } else {
      switch style {
      case .polaroid: preferredFraction = 0.74
      case .receipt: preferredFraction = 0.66
      case .poster: preferredFraction = 0.72
      default: preferredFraction = 0.70
      }
    }
    let minimumCaption = min(78, max(42, availableHeight * 0.20))
    let maximumImage = max(64, availableHeight - minimumCaption - spacing)
    let imageHeight = max(64, min(maximumImage, availableHeight * preferredFraction))
    let captionHeight = max(36, availableHeight - imageHeight - spacing)
    let lineLimit = textLength > 160 ? 4 : 3

    return MIRAWallPhotoNoteLayout(
      insets: insets,
      spacing: spacing,
      imageHeight: imageHeight,
      captionHeight: captionHeight,
      lineLimit: lineLimit
    )
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
        MIRAWallMaskingTape(seed: note.id, darkPaper: presentation.usesDarkPaper)
          .frame(width: max(40, 58 * zoom), height: max(10, 14 * zoom))
          .rotationEffect(.degrees(presentation.microRotation * -0.58))
          .offset(x: -MIRAWallLight.castX * 0.25, y: -6)
        Spacer()
      }
    case .pin:
      VStack {
        MIRAWallPushPin(color: pinColor)
          .frame(width: max(13, 18 * zoom), height: max(15, 21 * zoom))
          .offset(x: -MIRAWallLight.castX * 0.35, y: -8)
        Spacer()
      }
    case .paperclip:
      VStack {
        HStack {
          MIRAWallPaperClip(seed: note.id)
            .frame(width: max(21, 28 * zoom), height: max(31, 42 * zoom))
            .rotationEffect(.degrees(-12 + presentation.microRotation * 0.4))
            .offset(y: -10)
          Spacer()
        }
        Spacer()
      }
      .padding(.leading, 8)
    case .foldedCorner:
      VStack {
        HStack {
          Spacer()
          MIRAWallFoldedCorner(darkPaper: presentation.usesDarkPaper)
            .frame(width: max(17, 27 * zoom), height: max(17, 27 * zoom))
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

private struct MIRAWallMaskingTape: View {
  let seed: String
  let darkPaper: Bool

  var body: some View {
    MIRAWallTapeShape(seed: seed)
      .fill(darkPaper ? Color.white.opacity(0.28) : Color(red: 0.97, green: 0.95, blue: 0.83).opacity(0.58))
      .overlay {
        Canvas { context, size in
          let hash = MIRAWallNotePresentationResolver.stableHash("tape:\(seed)")
          for index in 0..<3 {
            let y = size.height * (0.28 + CGFloat(index) * 0.22)
            var wrinkle = Path()
            wrinkle.move(to: CGPoint(x: size.width * 0.08, y: y))
            wrinkle.addCurve(
              to: CGPoint(x: size.width * 0.92, y: y + MIRAWallMaterialNoise.unit(hash, index) * 1.2),
              control1: CGPoint(x: size.width * 0.34, y: y - 0.8),
              control2: CGPoint(x: size.width * 0.64, y: y + 0.9)
            )
            context.stroke(wrinkle, with: .color(Color.white.opacity(0.16)), lineWidth: 0.45)
          }
        }
        .clipShape(MIRAWallTapeShape(seed: seed))
      }
      .overlay {
        MIRAWallTapeShape(seed: seed)
          .stroke(Color.white.opacity(0.18), lineWidth: 0.45)
      }
      .shadow(
        color: .black.opacity(0.12),
        radius: 1.2,
        x: MIRAWallLight.contactX,
        y: MIRAWallLight.contactY
      )
  }
}

private struct MIRAWallPushPin: View {
  let color: Color

  var body: some View {
    ZStack {
      Ellipse()
        .fill(Color.black.opacity(0.12))
        .frame(width: 13, height: 6)
        .offset(x: MIRAWallLight.castX * 0.45, y: 6)

      Capsule()
        .fill(Color.black.opacity(0.38))
        .frame(width: 2, height: 9)
        .rotationEffect(.degrees(-15))
        .offset(x: 2.5, y: 5)

      Circle()
        .fill(
          RadialGradient(
            colors: [Color.white.opacity(0.72), color, color.opacity(0.72)],
            center: .topLeading,
            startRadius: 0,
            endRadius: 10
          )
        )
        .frame(width: 13, height: 13)
        .overlay(alignment: .topLeading) {
          Circle().fill(Color.white.opacity(0.48)).frame(width: 3.2, height: 3.2).padding(2.2)
        }
        .shadow(
          color: .black.opacity(0.27),
          radius: 1.5,
          x: MIRAWallLight.contactX,
          y: MIRAWallLight.contactY
        )
    }
  }
}

private struct MIRAWallPaperClip: View {
  let seed: String

  var body: some View {
    Canvas { context, size in
      let inset = max(2, size.width * 0.16)
      var outer = Path()
      outer.move(to: CGPoint(x: size.width * 0.68, y: 0))
      outer.addCurve(
        to: CGPoint(x: inset, y: size.height * 0.64),
        control1: CGPoint(x: size.width * 0.96, y: size.height * 0.18),
        control2: CGPoint(x: size.width * 0.80, y: size.height * 0.68)
      )
      outer.addCurve(
        to: CGPoint(x: size.width * 0.52, y: size.height * 0.88),
        control1: CGPoint(x: 0, y: size.height * 0.80),
        control2: CGPoint(x: size.width * 0.22, y: size.height)
      )
      outer.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.43))

      context.stroke(
        outer,
        with: .color(Color.black.opacity(0.20)),
        style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
      )
      context.stroke(
        outer,
        with: .linearGradient(
          Gradient(colors: [Color.white.opacity(0.82), Color.gray.opacity(0.72), Color.white.opacity(0.52)]),
          startPoint: .zero,
          endPoint: CGPoint(x: size.width, y: size.height)
        ),
        style: StrokeStyle(lineWidth: 1.65, lineCap: .round, lineJoin: .round)
      )

      var edgeWrap = Path()
      edgeWrap.move(to: CGPoint(x: size.width * 0.10, y: size.height * 0.24))
      edgeWrap.addLine(to: CGPoint(x: size.width * 0.78, y: size.height * 0.24))
      context.stroke(edgeWrap, with: .color(Color.black.opacity(0.18)), lineWidth: 0.8)
    }
    .allowsHitTesting(false)
  }
}

private struct MIRAWallFoldedCorner: View {
  let darkPaper: Bool

  var body: some View {
    ZStack(alignment: .topTrailing) {
      MIRAWallFoldShape()
        .fill(Color.black.opacity(0.10))
        .offset(x: MIRAWallLight.castX * 0.5, y: MIRAWallLight.castY * 0.45)
      MIRAWallFoldShape()
        .fill(darkPaper ? Color.white.opacity(0.16) : Color.white.opacity(0.46))
      MIRAWallFoldShape()
        .stroke(darkPaper ? Color.white.opacity(0.16) : Color.black.opacity(0.09), lineWidth: 0.55)
    }
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

private struct MIRAWallPaperMaterialLayer: View {
  let seed: String
  let material: MIRAWallPaperMaterial
  let darkPaper: Bool
  let detail: MIRAWallNoteRenderDetail

  var body: some View {
    Canvas { context, size in
      let hash = MIRAWallNotePresentationResolver.stableHash(seed)
      drawTonalVariation(context: &context, size: size, hash: hash)
      drawFibers(context: &context, size: size, hash: hash)
      drawMaterialMarks(context: &context, size: size, hash: hash)
      drawEdgeAge(context: &context, size: size)
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func drawTonalVariation(context: inout GraphicsContext, size: CGSize, hash: UInt64) {
    let count = detail == .distant ? 4 : 5
    for index in 0..<count {
      let x = size.width * MIRAWallMaterialNoise.unit(hash, index * 5 + 1)
      let y = size.height * MIRAWallMaterialNoise.unit(hash, index * 5 + 2)
      let width = size.width * (0.16 + MIRAWallMaterialNoise.unit(hash, index * 5 + 3) * 0.30)
      let height = size.height * (0.10 + MIRAWallMaterialNoise.unit(hash, index * 5 + 4) * 0.22)
      let color = index.isMultiple(of: 2) ? warmTone : coolTone
      context.fill(
        Path(ellipseIn: CGRect(x: x - width * 0.5, y: y - height * 0.5, width: width, height: height)),
        with: .color(color)
      )
    }
  }

  private func drawFibers(context: inout GraphicsContext, size: CGSize, hash: UInt64) {
    let baseCount: Int
    switch material {
    case .kraft, .aged: baseCount = 34
    case .notebook, .graph, .ivory: baseCount = 24
    case .photographic, .coated: baseCount = 12
    }
    let count = detail == .distant ? max(12, baseCount / 2) : baseCount
    for index in 0..<count {
      let x = size.width * MIRAWallMaterialNoise.unit(hash, 100 + index * 4)
      let y = size.height * MIRAWallMaterialNoise.unit(hash, 101 + index * 4)
      let length = 2.5 + MIRAWallMaterialNoise.unit(hash, 102 + index * 4) * (material == .kraft ? 13 : 8)
      let angle = (MIRAWallMaterialNoise.unit(hash, 103 + index * 4) - 0.5) * 0.55
      var fiber = Path()
      fiber.move(to: CGPoint(x: x, y: y))
      fiber.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
      context.stroke(
        fiber,
        with: .color(fiberColor.opacity(
          detail == .distant
            ? (material == .kraft ? 0.14 : 0.085)
            : (material == .kraft ? 0.085 : 0.045)
        )),
        style: StrokeStyle(
          lineWidth: detail == .distant
            ? (material == .kraft ? 1.15 : 0.82)
            : (material == .kraft ? 0.55 : 0.36),
          lineCap: .round
        )
      )
    }
  }

  private func drawMaterialMarks(context: inout GraphicsContext, size: CGSize, hash: UInt64) {
    switch material {
    case .notebook:
      let lineOpacity = detail == .distant ? 0.16 : 0.105
      let lineWidth: CGFloat = detail == .distant ? 1.15 : 0.55
      var y: CGFloat = 28
      while y < size.height {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: size.width, y: y + 0.15))
        context.stroke(line, with: .color(Color.blue.opacity(lineOpacity)), lineWidth: lineWidth)
        y += 22
      }
      var margin = Path()
      margin.move(to: CGPoint(x: min(29, size.width * 0.14), y: 0))
      margin.addLine(to: CGPoint(x: min(29, size.width * 0.14), y: size.height))
      context.stroke(
        margin,
        with: .color(Color.red.opacity(detail == .distant ? 0.20 : 0.15)),
        lineWidth: detail == .distant ? 1.35 : 0.7
      )
    case .graph:
      let spacing: CGFloat = 18
      let gridOpacity = detail == .distant ? 0.12 : 0.075
      let gridWidth: CGFloat = detail == .distant ? 0.95 : 0.45
      var x: CGFloat = spacing
      while x < size.width {
        var line = Path()
        line.move(to: CGPoint(x: x, y: 0))
        line.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(line, with: .color(Color.blue.opacity(gridOpacity)), lineWidth: gridWidth)
        x += spacing
      }
      var y: CGFloat = spacing
      while y < size.height {
        var line = Path()
        line.move(to: CGPoint(x: 0, y: y))
        line.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(line, with: .color(Color.blue.opacity(gridOpacity)), lineWidth: gridWidth)
        y += spacing
      }
    case .kraft:
      let speckleCount = detail == .distant ? 16 : 28
      for index in 0..<speckleCount {
        let x = size.width * MIRAWallMaterialNoise.unit(hash, 400 + index * 3)
        let y = size.height * MIRAWallMaterialNoise.unit(hash, 401 + index * 3)
        let baseRadius: CGFloat = detail == .distant ? 0.85 : 0.35
        let radiusRange: CGFloat = detail == .distant ? 1.25 : 0.75
        let radius = baseRadius + MIRAWallMaterialNoise.unit(hash, 402 + index * 3) * radiusRange
        context.fill(
          Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius * 0.72)),
          with: .color(Color.black.opacity(0.10))
        )
      }
    case .photographic:
      context.fill(
        Path(CGRect(
          x: 0,
          y: 0,
          width: size.width,
          height: max(detail == .distant ? 3 : 1, size.height * 0.018)
        )),
        with: .color(Color.white.opacity(0.16))
      )
    case .aged, .ivory, .coated:
      break
    }
  }

  private func drawEdgeAge(context: inout GraphicsContext, size: CGSize) {
    let opacity: Double
    switch material {
    case .aged: opacity = detail == .distant ? 0.13 : 0.075
    case .kraft: opacity = detail == .distant ? 0.09 : 0.045
    case .ivory, .notebook, .graph: opacity = detail == .distant ? 0.052 : 0.024
    case .photographic, .coated: opacity = detail == .distant ? 0.032 : 0.014
    }
    let edge = darkPaper ? Color.white.opacity(opacity * 0.45) : Color(red: 0.38, green: 0.24, blue: 0.12).opacity(opacity)
    let narrowEdge: CGFloat = detail == .distant ? 3.2 : 1.2
    let wideEdge: CGFloat = detail == .distant ? 3.8 : 1.8
    context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: narrowEdge)), with: .color(edge))
    context.fill(Path(CGRect(x: 0, y: size.height - wideEdge, width: size.width, height: wideEdge)), with: .color(edge))
    context.fill(Path(CGRect(x: 0, y: 0, width: narrowEdge, height: size.height)), with: .color(edge))
    context.fill(Path(CGRect(x: size.width - wideEdge, y: 0, width: wideEdge, height: size.height)), with: .color(edge))
  }

  private var fiberColor: Color {
    darkPaper ? Color.white : Color(red: 0.24, green: 0.18, blue: 0.11)
  }

  private var warmTone: Color {
    darkPaper
      ? Color.white.opacity(detail == .distant ? 0.018 : 0.008)
      : Color(red: 0.57, green: 0.38, blue: 0.16).opacity(
        material == .aged
          ? (detail == .distant ? 0.052 : 0.032)
          : (detail == .distant ? 0.028 : 0.014)
      )
  }

  private var coolTone: Color {
    darkPaper
      ? Color.black.opacity(detail == .distant ? 0.030 : 0.018)
      : Color(red: 0.30, green: 0.39, blue: 0.43)
        .opacity(detail == .distant ? 0.022 : 0.010)
  }
}

private struct MIRAWallPhotoPrintTexture: View {
  let seed: String

  var body: some View {
    Canvas { context, size in
      let hash = MIRAWallNotePresentationResolver.stableHash("photo:\(seed)")
      for index in 0..<22 {
        let x = size.width * MIRAWallMaterialNoise.unit(hash, index * 3)
        let y = size.height * MIRAWallMaterialNoise.unit(hash, index * 3 + 1)
        let radius = 0.35 + MIRAWallMaterialNoise.unit(hash, index * 3 + 2) * 0.45
        context.fill(
          Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
          with: .color((index.isMultiple(of: 2) ? Color.white : Color.black).opacity(0.025))
        )
      }
      context.fill(
        Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)),
        with: .color(Color(red: 0.98, green: 0.94, blue: 0.84).opacity(0.018))
      )
    }
    .allowsHitTesting(false)
  }
}

enum MIRAWallMaterialNoise {
  static func unit(_ seed: UInt64, _ salt: Int) -> CGFloat {
    var mixed = seed &+ UInt64(max(0, salt) + 1) &* 0x9E3779B97F4A7C15
    mixed ^= mixed >> 30
    mixed &*= 0xBF58476D1CE4E5B9
    mixed ^= mixed >> 27
    mixed &*= 0x94D049BB133111EB
    mixed ^= mixed >> 31
    return CGFloat(mixed % 10_000) / 10_000
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

private struct MIRAWallImperfectPaperShape: Shape {
  let seed: String
  let roughness: CGFloat

  func path(in rect: CGRect) -> Path {
    let hash = MIRAWallNotePresentationResolver.stableHash("edge:\(seed)")
    let segments = 14
    var points: [CGPoint] = []
    points.reserveCapacity((segments + 1) * 4)

    for index in 0...segments {
      let progress = CGFloat(index) / CGFloat(segments)
      points.append(CGPoint(
        x: rect.minX + rect.width * progress,
        y: rect.minY + 0.8 + jitter(hash, index, roughness)
      ))
    }
    for index in 1...segments {
      let progress = CGFloat(index) / CGFloat(segments)
      points.append(CGPoint(
        x: rect.maxX - 0.8 + jitter(hash, 100 + index, roughness),
        y: rect.minY + rect.height * progress
      ))
    }
    for index in (0..<segments).reversed() {
      let progress = CGFloat(index) / CGFloat(segments)
      points.append(CGPoint(
        x: rect.minX + rect.width * progress,
        y: rect.maxY - 0.8 + jitter(hash, 200 + index, roughness)
      ))
    }
    for index in (1..<segments).reversed() {
      let progress = CGFloat(index) / CGFloat(segments)
      points.append(CGPoint(
        x: rect.minX + 0.8 + jitter(hash, 300 + index, roughness),
        y: rect.minY + rect.height * progress
      ))
    }

    var path = Path()
    if let first = points.first { path.move(to: first) }
    for point in points.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
  }

  private func jitter(_ hash: UInt64, _ salt: Int, _ amount: CGFloat) -> CGFloat {
    (MIRAWallMaterialNoise.unit(hash, salt) - 0.5) * amount * 2
  }
}

private struct MIRAWallPhotoCropShape: Shape {
  let seed: String

  func path(in rect: CGRect) -> Path {
    MIRAWallImperfectPaperShape(seed: "photo:\(seed)", roughness: 0.24).path(in: rect)
  }
}

private struct MIRAWallTapeShape: Shape {
  let seed: String

  func path(in rect: CGRect) -> Path {
    let hash = MIRAWallNotePresentationResolver.stableHash("tape-edge:\(seed)")
    let teeth = 8
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + 1))
    for index in 0...teeth {
      let y = rect.minY + rect.height * CGFloat(index) / CGFloat(teeth)
      let x = rect.minX + (MIRAWallMaterialNoise.unit(hash, index) - 0.5) * 2.4
      path.addLine(to: CGPoint(x: x, y: y))
    }
    for index in 0...teeth {
      let y = rect.maxY - rect.height * CGFloat(index) / CGFloat(teeth)
      let x = rect.maxX + (MIRAWallMaterialNoise.unit(hash, 100 + index) - 0.5) * 2.4
      path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
  }
}
private struct MIRAWallSoftScrapShape: Shape {
  let seed: String

  func path(in rect: CGRect) -> Path {
    let hash = MIRAWallNotePresentationResolver.stableHash("scrap:\(seed)")
    let top = 1.4 + MIRAWallMaterialNoise.unit(hash, 1) * 1.2
    let right = 1.2 + MIRAWallMaterialNoise.unit(hash, 2) * 1.1
    let bottom = 1.2 + MIRAWallMaterialNoise.unit(hash, 3) * 1.3
    let left = 1.2 + MIRAWallMaterialNoise.unit(hash, 4) * 1.1
    var path = Path()
    path.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + top))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - 3, y: rect.minY + top * 0.7),
      control: CGPoint(x: rect.midX, y: rect.minY - top * 0.35)
    )
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - right, y: rect.maxY - 2),
      control: CGPoint(x: rect.maxX + right * 0.45, y: rect.midY)
    )
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + 3, y: rect.maxY - bottom),
      control: CGPoint(x: rect.midX, y: rect.maxY + bottom * 0.55)
    )
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + 2, y: rect.minY + top),
      control: CGPoint(x: rect.minX - left * 0.45, y: rect.midY)
    )
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
