package expo.modules.miraperformance

import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class MiraPerformanceModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("MiraPerformance")

    Constant("nativeRuntime") {
      "kotlin"
    }

    Function("makeMediaCacheKey") { uri: String, width: Double, height: Double, preset: String ->
      stableHash("${uri}|${Math.round(width)}x${Math.round(height)}|${preset}")
    }

    Function("scoreFeedItem") {
      likes: Double,
      comments: Double,
      saves: Double,
      shares: Double,
      views: Double,
      ageHours: Double,
      isFollowed: Boolean,
      isVideo: Boolean ->
        val engagement = (likes * 3.0) + (comments * 6.0) + (saves * 7.0) + (shares * 8.0) + (views.coerceAtMost(5000.0) * 0.08)
        val recency = (72.0 - ageHours).coerceAtLeast(0.0) * 0.9
        val relationship = if (isFollowed) 18.0 else 0.0
        val mediaBoost = if (isVideo) 4.0 else 2.0
        engagement + recency + relationship + mediaBoost
    }

    Function("planMedia") {
      uri: String,
      mimeType: String,
      fileName: String,
      fileSize: Double,
      width: Double,
      height: Double,
      preset: String ->
        val kind = detectMediaKind(uri, mimeType, fileName)
        val unsafe = isUnsafeMedia(fileName, mimeType, uri)
        val maxBytes = if (kind == "video") 500 * 1024 * 1024 else 20 * 1024 * 1024
        val allowed = kind != "unknown" && !unsafe && fileSize <= maxBytes.toDouble()
        val sourceWidth = if (width > 0.0) width else if (kind == "video") 1080.0 else 1440.0
        val sourceHeight = if (height > 0.0) height else if (kind == "video") 1920.0 else 1920.0
        val maxLongEdge = if (kind == "video") 1920.0 else when (preset) {
          "quality" -> 3000.0
          "compact" -> 1280.0
          else -> 2200.0
        }
        val scale = (maxLongEdge / sourceWidth.coerceAtLeast(sourceHeight).coerceAtLeast(1.0)).coerceAtMost(1.0)
        val targetWidth = (sourceWidth * scale).coerceAtLeast(1.0).let { Math.round(it).toInt() }
        val targetHeight = (sourceHeight * scale).coerceAtLeast(1.0).let { Math.round(it).toInt() }
        val reason = when {
          kind == "unknown" -> "unknown_media_type"
          unsafe -> "blocked_unsafe_file_type"
          fileSize > maxBytes.toDouble() -> "file_too_large"
          else -> "ok"
        }
        val imageQuality = when (preset) {
          "quality" -> 0.92
          "compact" -> 0.84
          else -> 0.89
        }
        val videoBitrate = when (preset) {
          "quality" -> 12000000
          "compact" -> 5500000
          else -> 8000000
        }
        val cacheKey = stableHash("${uri}|${fileName}|${sourceWidth.toInt()}x${sourceHeight.toInt()}|${fileSize.toLong()}")
        """{"kind":"$kind","allowed":$allowed,"reason":"$reason","targetWidth":$targetWidth,"targetHeight":$targetHeight,"aspectRatio":${sourceWidth / sourceHeight.coerceAtLeast(1.0)},"maxBytes":$maxBytes,"targetMimeType":"${if (kind == "video") "video/mp4" else "image/jpeg"}","imageQuality":$imageQuality,"videoBitrate":$videoBitrate,"targetFps":30,"shouldUseThumbnail":${kind == "video"},"cacheKey":"$cacheKey"}"""
    }

    Function("nativeDesignProfile") {
      """{"runtime":"kotlin","platform":"android","surface":"#FFFFFF","surfaceSoft":"#FAFAF8","textPrimary":"#1D2119","textSecondary":"#687066","forest":"#20361F","forestPressed":"#172917","shadowColor":"#20361F","shadowOpacity":0.10,"radiusCard":22,"radiusSheet":28,"minTouchTarget":44}"""
    }
  }

  private fun stableHash(value: String): String {
    var hash = -3750763034362895579L
    value.toByteArray(Charsets.UTF_8).forEach { byte ->
      hash = hash xor (byte.toLong() and 0xff)
      hash *= 1099511628211L
    }
    return java.lang.Long.toUnsignedString(hash, 16)
  }

  private fun detectMediaKind(uri: String, mimeType: String, fileName: String): String {
    val lowerUri = uri.lowercase()
    val lowerMime = mimeType.lowercase()
    val ext = mediaExtension(if (fileName.isNotBlank()) fileName else uri)
    if (lowerUri.startsWith("cfstream:") || lowerMime.startsWith("video/") || lowerUri.startsWith("data:video/") || setOf("mp4", "mov", "m4v", "webm").contains(ext)) {
      return "video"
    }
    if (lowerMime.startsWith("image/") || lowerUri.startsWith("data:image/") || setOf("jpg", "jpeg", "png", "webp", "heic", "heif").contains(ext)) {
      return "image"
    }
    return "unknown"
  }

  private fun isUnsafeMedia(fileName: String, mimeType: String, uri: String): Boolean {
    val ext = mediaExtension(if (fileName.isNotBlank()) fileName else uri)
    return setOf("apk", "app", "bat", "cmd", "com", "dll", "dmg", "exe", "js", "msi", "ps1", "sh", "svg").contains(ext) || mimeType.lowercase().contains("svg")
  }

  private fun mediaExtension(value: String): String {
    val clean = value.substringBefore("?").substringBefore("#").lowercase()
    val ext = clean.substringAfterLast(".", "")
    return if (ext.length <= 8) ext else ""
  }
}
