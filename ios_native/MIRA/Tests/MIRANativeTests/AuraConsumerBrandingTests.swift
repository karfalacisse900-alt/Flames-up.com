import Foundation
import XCTest

final class AuraConsumerBrandingTests: XCTestCase {
  private var miraRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
  }

  private func source(_ relativePath: String) throws -> String {
    try String(
      contentsOf: miraRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }

  func testReachableConsumerCopyDoesNotUseLegacyProductNames() throws {
    let files = [
      "Sources/MIRANative/Services/MIRALocalization.swift",
      "Sources/MIRANative/Screens/SettingsNativeView.swift",
      "Sources/MIRANative/Screens/LegalNativeViews.swift",
      "Sources/MIRANative/Services/MIRAMediaUploadService.swift",
      "Sources/MIRANative/Screens/ProfileChatVerificationStudio.swift"
    ]
    let stringLiteralPattern = try NSRegularExpression(pattern: #""(?:\\.|[^"\\])*""#)

    for relativePath in files {
      let contents = try source(relativePath)
      let range = NSRange(contents.startIndex..., in: contents)
      let literals = stringLiteralPattern.matches(in: contents, range: range).compactMap { match -> String? in
        guard let swiftRange = Range(match.range, in: contents) else { return nil }
        return String(contents[swiftRange])
      }
      let legacyConsumerLiterals = literals.filter { literal in
        guard !literal.contains("CaptroCameraQuality") else { return false }
        return literal.contains("Captro") || literal.contains("Flames-Up") || literal.contains("Flames Up")
      }

      XCTAssertTrue(
        legacyConsumerLiterals.isEmpty,
        "Legacy consumer branding remains in \(relativePath): \(legacyConsumerLiterals)"
      )
    }
  }

  func testPublicProfileFallbackAndModerationCopyUseAura() throws {
    let profile = try source("Sources/MIRANative/Screens/ProfileChatVerificationStudio.swift")

    XCTAssertFalse(profile.contains(#"?? "captro""#))
    XCTAssertTrue(profile.contains(#"?? "Aura member""#))
    XCTAssertTrue(profile.contains("Send this profile to Aura moderation."))
    XCTAssertTrue(profile.contains("protect your Aura account"))
  }

  func testCompatibilityIdentifiersRemainStable() throws {
    let localization = try source("Sources/MIRANative/Services/MIRALocalization.swift")
    let legal = try source("Sources/MIRANative/Screens/LegalNativeViews.swift")
    let media = try source("Sources/MIRANative/Services/MIRAMediaUploadService.swift")

    XCTAssertTrue(localization.contains(#""captro.language.preference""#))
    XCTAssertTrue(legal.contains(#""https://captro.app""#))
    XCTAssertTrue(media.contains("CaptroCameraQuality"))
  }
}
