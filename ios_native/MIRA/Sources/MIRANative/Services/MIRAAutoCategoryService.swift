import AVFoundation
import Foundation
import UIKit
import Vision

public struct MIRAAutoCategoryLabel: Codable, Hashable {
  public let label: String
  public let confidence: Double

  public init(label: String, confidence: Double) {
    self.label = label
    self.confidence = confidence
  }
}

public struct MIRAAutoCategorySignals: Encodable, Hashable {
  public let appleVisionLabels: [MIRAAutoCategoryLabel]
  public let appleVisionCategoryGuess: String?
  public let appleVisionConfidence: Double?

  public static let empty = MIRAAutoCategorySignals(
    appleVisionLabels: [],
    appleVisionCategoryGuess: nil,
    appleVisionConfidence: nil
  )
}

public enum MIRAAutoCategoryService {
  private static let categoryKeywords: [String: [String]] = [
    "outfits": ["outfit", "fit", "fit check", "clothes", "style", "fashion", "streetwear", "shoes", "shoe", "jacket", "mirror selfie", "clothing", "accessories", "sneakers", "dress", "apparel", "person"],
    "outdoors": ["outdoors", "outdoor", "outside", "park", "beach", "hiking", "trail", "nature", "mountain", "lake", "sunset", "sunrise", "trees", "tree", "forest", "walking", "landscape", "snow", "sky", "water", "river", "ocean", "sea", "flower", "plant", "grass", "garden", "field", "woods", "camping"],
    "events": ["event", "concert", "festival", "meetup", "show", "game", "crowd", "stadium", "venue", "performance", "birthday", "wedding", "audience", "stage", "party", "celebration"],
    "nightlife": ["nightlife", "night", "club", "bar", "lounge", "party", "rooftop", "dj", "drinks", "city night", "after dark", "dance", "neon", "dark", "cocktail", "evening"],
    "travel": ["travel", "trip", "vacation", "hotel", "airport", "landmark", "city visit", "tourist", "destination", "road trip", "passport", "flight", "city", "street", "architecture", "building", "castle", "monument", "bridge", "train", "station", "historic", "old town", "view"],
    "photography": ["photography", "portrait", "camera", "photo shoot", "street photo", "aesthetic", "landscape shot", "creative shot", "close up", "close-up", "lens", "film", "macro", "black and white", "monochrome", "composition"],
    "art": ["art", "drawing", "painting", "design", "sketch", "illustration", "mural", "gallery", "creative work", "museum", "artist", "craft", "sculpture", "visual art"],
    "fitness": ["gym", "workout", "running", "fitness", "sport", "basketball", "soccer", "training", "yoga", "exercise", "athlete", "cycling", "bike", "bicycle"],
    "lifestyle": ["daily life", "friends", "home", "routine", "random moment", "personal moment", "general capture", "selfie", "room", "people", "human", "family"]
  ]

  public static func analyze(
    mediaItems: [MIRAPickedMedia],
    title: String,
    caption: String,
    hashtags: [String],
    placeName: String?,
    location: String?
  ) async -> MIRAAutoCategorySignals {
    guard !mediaItems.isEmpty else {
      return score(labels: [], title: title, caption: caption, hashtags: hashtags, placeName: placeName, location: location)
    }

    return await Task.detached(priority: .utility) {
      var labelScores: [String: Double] = [:]
      for media in mediaItems.prefix(3) {
        let labels: [MIRAAutoCategoryLabel]
        switch media.kind {
        case .image:
          labels = Self.classifyImageData(media.data)
        case .video:
          labels = Self.classifyVideoKeyframes(media)
        }
        for label in labels {
          labelScores[label.label] = max(labelScores[label.label] ?? 0, label.confidence)
        }
      }

      let mergedLabels = labelScores
        .map { MIRAAutoCategoryLabel(label: $0.key, confidence: $0.value) }
        .sorted { $0.confidence > $1.confidence }
        .prefix(14)
      return Self.score(
        labels: Array(mergedLabels),
        title: title,
        caption: caption,
        hashtags: hashtags,
        placeName: placeName,
        location: location
      )
    }.value
  }

  private static func classifyImageData(_ data: Data) -> [MIRAAutoCategoryLabel] {
    guard let image = UIImage(data: data), let cgImage = Self.resizedCGImage(from: image) else { return [] }
    return Self.classify(cgImage: cgImage)
  }

  private static func classifyVideoKeyframes(_ media: MIRAPickedMedia) -> [MIRAAutoCategoryLabel] {
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(media.fileName)
    do {
      try media.data.write(to: tempURL, options: .atomic)
      defer { try? FileManager.default.removeItem(at: tempURL) }
      let asset = AVAsset(url: tempURL)
      let duration = max(0.6, asset.duration.seconds.isFinite ? asset.duration.seconds : 0.6)
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = CGSize(width: 512, height: 512)
      let seconds = Array(Set([0.1, duration * 0.33, duration * 0.66].map { min(max($0, 0.1), max(duration - 0.1, 0.1)) })).sorted()
      var labelScores: [String: Double] = [:]
      for second in seconds.prefix(3) {
        let time = CMTime(seconds: second, preferredTimescale: 600)
        guard let frame = try? generator.copyCGImage(at: time, actualTime: nil) else { continue }
        for label in Self.classify(cgImage: frame) {
          labelScores[label.label] = max(labelScores[label.label] ?? 0, label.confidence)
        }
      }
      return labelScores
        .map { MIRAAutoCategoryLabel(label: $0.key, confidence: $0.value) }
        .sorted { $0.confidence > $1.confidence }
    } catch {
      return []
    }
  }

  private static func classify(cgImage: CGImage) -> [MIRAAutoCategoryLabel] {
    let request = VNClassifyImageRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
      return (request.results ?? [])
        .prefix(10)
        .map { MIRAAutoCategoryLabel(label: $0.identifier.lowercased(), confidence: Double($0.confidence)) }
    } catch {
      return []
    }
  }

  private static func resizedCGImage(from image: UIImage) -> CGImage? {
    let maxSide: CGFloat = 512
    let size = image.size
    guard size.width > 0, size.height > 0 else { return image.cgImage }
    let scale = min(1, maxSide / max(size.width, size.height))
    if scale >= 1 { return image.cgImage }
    let target = CGSize(width: size.width * scale, height: size.height * scale)
    let renderer = UIGraphicsImageRenderer(size: target)
    let resized = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: target))
    }
    return resized.cgImage
  }

  private static func score(
    labels: [MIRAAutoCategoryLabel],
    title: String,
    caption: String,
    hashtags: [String],
    placeName: String?,
    location: String?
  ) -> MIRAAutoCategorySignals {
    var scores = Dictionary(uniqueKeysWithValues: categoryKeywords.keys.map { ($0, 0.0) })
    let text = ([title, caption, placeName, location] + hashtags).compactMap { $0 }.joined(separator: " ").lowercased()
    for (category, keywords) in categoryKeywords {
      for keyword in keywords where text.contains(keyword) {
        scores[category, default: 0] += hashtags.contains(where: { $0.lowercased().contains(keyword) }) ? 0.30 : 0.22
      }
    }
    for label in labels {
      for (category, keywords) in categoryKeywords {
        if keywords.contains(where: { label.label.contains($0) || $0.contains(label.label) }) {
          scores[category, default: 0] += min(0.36, label.confidence * 0.34)
        }
      }
    }
    let best = scores.max { $0.value < $1.value }
    let confidence = min(0.98, max(0, best?.value ?? 0))
    return MIRAAutoCategorySignals(
      appleVisionLabels: labels,
      appleVisionCategoryGuess: confidence >= 0.35 ? best?.key : nil,
      appleVisionConfidence: confidence >= 0.35 ? confidence : nil
    )
  }
}
