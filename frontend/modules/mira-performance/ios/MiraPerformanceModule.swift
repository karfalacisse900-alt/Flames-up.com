import ExpoModulesCore

public class MiraPerformanceModule: Module {
  public func definition() -> ModuleDefinition {
    Name("MiraPerformance")

    Constant("nativeRuntime") {
      "swift"
    }

    Function("makeMediaCacheKey") { (uri: String, width: Double, height: Double, preset: String) -> String in
      let normalized = "\(uri)|\(Int(width.rounded()))x\(Int(height.rounded()))|\(preset)"
      return stableHash(normalized)
    }

    Function("scoreFeedItem") { (
      likes: Double,
      comments: Double,
      saves: Double,
      shares: Double,
      views: Double,
      ageHours: Double,
      isFollowed: Bool,
      isVideo: Bool
    ) -> Double in
      let engagement = (likes * 3.0) + (comments * 6.0) + (saves * 7.0) + (shares * 8.0) + min(views, 5000.0) * 0.08
      let recency = max(0.0, 72.0 - ageHours) * 0.9
      let relationship = isFollowed ? 18.0 : 0.0
      let mediaBoost = isVideo ? 4.0 : 2.0
      return engagement + recency + relationship + mediaBoost
    }

    Function("planMedia") { (
      uri: String,
      mimeType: String,
      fileName: String,
      fileSize: Double,
      width: Double,
      height: Double,
      preset: String
    ) -> String in
      let kind = detectMediaKind(uri: uri, mimeType: mimeType, fileName: fileName)
      let allowedKind = kind != "unknown"
      let unsafe = isUnsafeMedia(fileName: fileName, mimeType: mimeType, uri: uri)
      let maxBytes = kind == "video" ? 500 * 1024 * 1024 : 20 * 1024 * 1024
      let allowed = allowedKind && !unsafe && fileSize <= Double(maxBytes)
      let sourceWidth = width > 0 ? width : (kind == "video" ? 1080 : 1440)
      let sourceHeight = height > 0 ? height : (kind == "video" ? 1920 : 1920)
      let maxLongEdge = kind == "video" ? 1920 : (preset == "quality" ? 3000 : (preset == "compact" ? 1280 : 2200))
      let longEdge = max(sourceWidth, sourceHeight)
      let scale = min(1.0, Double(maxLongEdge) / max(1.0, longEdge))
      let targetWidth = max(1, Int((sourceWidth * scale).rounded()))
      let targetHeight = max(1, Int((sourceHeight * scale).rounded()))
      let reason = !allowedKind ? "unknown_media_type" : unsafe ? "blocked_unsafe_file_type" : fileSize > Double(maxBytes) ? "file_too_large" : "ok"
      let imageQuality = preset == "quality" ? 0.92 : (preset == "compact" ? 0.84 : 0.89)
      let videoBitrate = preset == "quality" ? 12000000 : (preset == "compact" ? 5500000 : 8000000)
      let cacheKey = stableHash(uri + "|" + fileName + "|" + String(Int(sourceWidth)) + "x" + String(Int(sourceHeight)) + "|" + String(Int(fileSize)))
      let json = """
      {"kind":"\(kind)","allowed":\(allowed ? "true" : "false"),"reason":"\(reason)","targetWidth":\(targetWidth),"targetHeight":\(targetHeight),"aspectRatio":\(sourceWidth / max(1.0, sourceHeight)),"maxBytes":\(maxBytes),"targetMimeType":"\(kind == "video" ? "video/mp4" : "image/jpeg")","imageQuality":\(imageQuality),"videoBitrate":\(videoBitrate),"targetFps":30,"shouldUseThumbnail":\(kind == "video" ? "true" : "false"),"cacheKey":"\(cacheKey)"}
      """
      return json
    }

    Function("nativeDesignProfile") { () -> String in
      """
      {"runtime":"swift","platform":"ios","surface":"#FFFFFF","surfaceSoft":"#FAFAF8","textPrimary":"#1D2119","textSecondary":"#687066","forest":"#20361F","forestPressed":"#172917","shadowColor":"#20361F","shadowOpacity":0.10,"radiusCard":22,"radiusSheet":28,"minTouchTarget":44}
      """
    }
  }
}

private func stableHash(_ value: String) -> String {
  var hash: UInt64 = 1469598103934665603
  for byte in value.utf8 {
    hash ^= UInt64(byte)
    hash = hash &* 1099511628211
  }
  return String(hash, radix: 16)
}

private func detectMediaKind(uri: String, mimeType: String, fileName: String) -> String {
  let lowerUri = uri.lowercased()
  let lowerMime = mimeType.lowercased()
  let ext = mediaExtension(fileName.isEmpty ? uri : fileName)
  if lowerUri.hasPrefix("cfstream:") || lowerMime.hasPrefix("video/") || lowerUri.hasPrefix("data:video/") || ["mp4", "mov", "m4v", "webm"].contains(ext) {
    return "video"
  }
  if lowerMime.hasPrefix("image/") || lowerUri.hasPrefix("data:image/") || ["jpg", "jpeg", "png", "webp", "heic", "heif"].contains(ext) {
    return "image"
  }
  return "unknown"
}

private func isUnsafeMedia(fileName: String, mimeType: String, uri: String) -> Bool {
  let ext = mediaExtension(fileName.isEmpty ? uri : fileName)
  let blocked = ["apk", "app", "bat", "cmd", "com", "dll", "dmg", "exe", "js", "msi", "ps1", "sh", "svg"]
  return blocked.contains(ext) || mimeType.lowercased().contains("svg")
}

private func mediaExtension(_ value: String) -> String {
  let clean = value.components(separatedBy: CharacterSet(charactersIn: "?#")).first?.lowercased() ?? ""
  guard let dot = clean.lastIndex(of: ".") else { return "" }
  let ext = String(clean[clean.index(after: dot)...])
  return ext.count <= 8 ? ext : ""
}
