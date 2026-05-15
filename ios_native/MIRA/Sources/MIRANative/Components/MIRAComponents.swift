import AVKit
import SwiftUI
import UIKit

public struct MIRAPrimaryButton: View {
  let title: String
  let systemImage: String?
  let action: () -> Void

  public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
    self.title = title
    self.systemImage = systemImage
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      HStack(spacing: MIRATheme.Space.xs) {
        if let systemImage {
          Image(systemName: systemImage)
        }
        Text(title).font(.system(size: 16, weight: .semibold))
      }
      .foregroundStyle(.white)
      .frame(minHeight: 44)
      .padding(.horizontal, MIRATheme.Space.lg)
      .background(MIRATheme.Color.forest)
      .clipShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

public struct MIRAIconButton: View {
  let systemImage: String
  let action: () -> Void

  public var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
        .frame(width: 44, height: 44)
        .background(MIRATheme.Color.surfaceSoft)
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
  }
}

public struct MIRAHeaderCircleButton: View {
  let systemImage: String

  public init(systemImage: String) {
    self.systemImage = systemImage
  }

  public var body: some View {
    Image(systemName: systemImage)
      .font(.system(size: 17, weight: .semibold))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(width: 40, height: 40)
      .background(MIRATheme.Color.surfaceSoft)
      .clipShape(Circle())
  }
}

public struct MIRAEmptyState: View {
  let title: String
  let message: String
  let systemImage: String

  public var body: some View {
    VStack(spacing: MIRATheme.Space.md) {
      Image(systemName: systemImage)
        .font(.system(size: 42, weight: .light))
        .foregroundStyle(MIRATheme.Color.textMuted)
      Text(title)
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(MIRATheme.Color.textPrimary)
      Text(message)
        .font(.system(size: 15, weight: .regular))
        .foregroundStyle(MIRATheme.Color.textSecondary)
        .multilineTextAlignment(.center)
    }
    .padding(MIRATheme.Space.xxl)
    .frame(maxWidth: .infinity)
  }
}

public struct RemoteAvatar: View {
  let url: String?
  let size: CGFloat

  public var body: some View {
    AsyncImage(url: URL(string: url ?? "")) { phase in
      switch phase {
      case .success(let image):
        image.resizable().scaledToFill()
      default:
        ZStack {
          MIRATheme.Color.surfaceSoft
          Image(systemName: "person.fill")
            .foregroundStyle(MIRATheme.Color.textMuted)
        }
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}

public struct MIRAFollowAvatar: View {
  let url: String?
  let size: CGFloat
  let isFollowing: Bool

  public init(url: String?, size: CGFloat, isFollowing: Bool = false) {
    self.url = url
    self.size = size
    self.isFollowing = isFollowing
  }

  public var body: some View {
    ZStack(alignment: .bottomTrailing) {
      RemoteAvatar(url: url, size: size)
      Circle()
        .fill(isFollowing ? MIRATheme.Color.textPrimary : MIRATheme.Color.forest)
        .frame(width: max(18, size * 0.42), height: max(18, size * 0.42))
        .overlay {
          Image(systemName: isFollowing ? "checkmark" : "plus")
            .font(.system(size: max(9, size * 0.22), weight: .bold))
            .foregroundStyle(.white)
        }
        .overlay(Circle().stroke(MIRATheme.Color.surface, lineWidth: 2))
        .offset(x: 2, y: 2)
    }
  }
}

public struct RemoteMediaView: View {
  let url: String
  let isVideo: Bool
  let contentMode: ContentMode

  public init(url: String, isVideo: Bool, contentMode: ContentMode = .fill) {
    self.url = url
    self.isVideo = isVideo
    self.contentMode = contentMode
  }

  public var body: some View {
    Group {
      if isVideo, let videoURL = URL(string: url) {
        VideoPlayer(player: AVPlayer(url: videoURL))
      } else {
        AsyncImage(url: URL(string: url)) { phase in
          switch phase {
          case .success(let image):
            image.resizable().aspectRatio(contentMode: contentMode)
          case .failure:
            placeholder
          default:
            placeholder.redacted(reason: .placeholder)
          }
        }
      }
    }
    .clipped()
  }

  private var placeholder: some View {
    ZStack {
      MIRATheme.Color.surfaceSoft
      Image(systemName: "photo")
        .font(.system(size: 28, weight: .light))
        .foregroundStyle(MIRATheme.Color.textMuted)
    }
  }
}

public struct MIRAAdaptiveMediaView: View {
  let urls: [String]
  let cornerRadius: CGFloat
  let maxSingleImageHeight: CGFloat
  let carouselHeight: CGFloat

  public init(
    urls: [String],
    cornerRadius: CGFloat = 0,
    maxSingleImageHeight: CGFloat = min(UIScreen.main.bounds.width * 1.18, 560),
    carouselHeight: CGFloat = min(UIScreen.main.bounds.width * 1.08, 520)
  ) {
    self.urls = urls
    self.cornerRadius = cornerRadius
    self.maxSingleImageHeight = maxSingleImageHeight
    self.carouselHeight = carouselHeight
  }

  public var body: some View {
    Group {
      if let url = urls.first, urls.count == 1, !url.isVideoURL {
        RemoteMediaView(url: url, isVideo: false, contentMode: .fit)
          .frame(maxWidth: .infinity)
          .frame(
            minHeight: min(UIScreen.main.bounds.width * 0.62, maxSingleImageHeight),
            maxHeight: maxSingleImageHeight
          )
          .background(MIRATheme.Color.surfaceSoft)
      } else {
        TabView {
          ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
            RemoteMediaView(url: url, isVideo: url.isVideoURL)
          }
        }
        .tabViewStyle(.page(indexDisplayMode: urls.count > 1 ? .automatic : .never))
        .frame(maxWidth: .infinity)
        .frame(height: carouselHeight)
        .background(MIRATheme.Color.surfaceSoft)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
  }
}

public struct MIRAStatButton: View {
  let systemImage: String
  let value: Int
  let action: () -> Void

  public var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Image(systemName: systemImage)
        Text(compact(value))
      }
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(MIRATheme.Color.textPrimary)
      .frame(minHeight: 44)
    }
    .buttonStyle(.plain)
  }

  private func compact(_ value: Int) -> String {
    if value >= 1_000_000 { return "\(value / 1_000_000)M" }
    if value >= 1_000 { return "\(value / 1_000)K" }
    return "\(value)"
  }
}

extension String {
  var isVideoURL: Bool {
    let lower = lowercased()
    return lower.contains(".mp4") || lower.contains(".mov") || lower.contains(".m3u8") || lower.contains("stream")
  }
}
