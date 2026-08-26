import Foundation
import XCTest

final class AuraTactileDesignTests: XCTestCase {
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

  func testAuraPaperPaletteAndHardShadowRemainExplicit() throws {
    let theme = try source("Sources/MIRANative/Design/MIRATheme.swift")
    let community = try source("Sources/MIRANative/Screens/Aura/AuraCommunityViews.swift")
    let components = try source("Sources/MIRANative/Components/AuraMobileComponents.swift")

    XCTAssertTrue(theme.contains("public static let paperCanvas"))
    XCTAssertTrue(theme.contains("light: UIColor(red: 0.988, green: 0.949, blue: 0.859"))
    XCTAssertTrue(theme.contains("public static let paperSurface"))
    XCTAssertTrue(theme.contains("light: UIColor(red: 1.000, green: 1.000, blue: 0.918"))
    XCTAssertTrue(theme.contains("public static let inkBorder"))
    XCTAssertTrue(theme.contains("public static let hardShadow"))

    XCTAssertTrue(community.contains(".stroke(MIRATheme.Color.inkBorder, lineWidth: 1.5)"))
    XCTAssertTrue(community.contains(".shadow(color: MIRATheme.Color.hardShadow, radius: 0, x: 0, y: 5)"))
    XCTAssertTrue(components.contains("AuraTactilePrimaryButtonStyle"))
    XCTAssertTrue(components.contains("AuraTactileSecondaryButtonStyle"))
  }

  func testHomeKeepsCompactSmallPostsAndPhotoLedMeetupsWithoutGlass() throws {
    let home = try source("Sources/MIRANative/Screens/Aura/AuraHomeView.swift")
    let community = try source("Sources/MIRANative/Screens/Aura/AuraCommunityViews.swift")
    let source = home + community

    XCTAssertTrue(home.contains("MIRATheme.Color.paperCanvas.ignoresSafeArea()"))
    XCTAssertTrue(home.contains("LazyVStack(spacing: 12)"))
    XCTAssertTrue(community.contains("AuraSmallPostFeedCard"))
    XCTAssertTrue(community.contains("AuraCommunityPostMedia(post: post, height: 64)"))
    XCTAssertTrue(community.contains("AuraMeetupFeedCard"))
    XCTAssertTrue(community.contains("AuraCommunityPostMedia(post: post, height: 184)"))
    XCTAssertTrue(community.contains("AuraCommunityPostMedia(post: post, height: 270, playsVideo: true)"))
    XCTAssertFalse(source.contains("LinearGradient"))
    XCTAssertFalse(source.localizedCaseInsensitiveContains("ultraThinMaterial"))
    XCTAssertFalse(source.localizedCaseInsensitiveContains("glass"))
  }

  func testScanUsesAutomaticAuraCopyAndTactileActions() throws {
    let scan = try source("Sources/MIRANative/Screens/Aura/AuraScanView.swift")

    XCTAssertTrue(scan.contains("Aura automatically recognizes receipts and invoices."))
    XCTAssertTrue(scan.contains("AuraTactilePrimaryButtonStyle"))
    XCTAssertTrue(scan.contains("AuraTactileSecondaryButtonStyle"))
    XCTAssertTrue(scan.contains("MIRATheme.Color.paperCanvas.ignoresSafeArea()"))
    XCTAssertTrue(scan.contains("private var scanStage"))
    XCTAssertFalse(scan.localizedCaseInsensitiveContains("veryfi"))
    XCTAssertFalse(scan.localizedCaseInsensitiveContains("provider"))
    XCTAssertFalse(scan.contains("LinearGradient"))
    XCTAssertFalse(scan.localizedCaseInsensitiveContains("material"))
  }

  func testWalletMeAndFourTabChromeShareThePaperAndInkSystem() throws {
    let wallet = try source("Sources/MIRANative/Screens/Aura/AuraWalletView.swift")
    let me = try source("Sources/MIRANative/Screens/Aura/AuraMeView.swift")
    let root = try source("Sources/MIRANative/App/MIRANativeRootView.swift")
    let source = wallet + me + root

    XCTAssertTrue(wallet.contains("MIRATheme.Color.paperCanvas.ignoresSafeArea()"))
    XCTAssertTrue(wallet.contains(".shadow(\n        color: MIRATheme.Color.hardShadow"))
    XCTAssertTrue(wallet.contains("gateway.availableAUR"))
    XCTAssertTrue(wallet.contains("Network data not connected"))
    XCTAssertTrue(wallet.contains("Unavailable"))

    XCTAssertTrue(me.contains("MIRATheme.Color.paperCanvas.ignoresSafeArea()"))
    XCTAssertTrue(me.contains("AuraTactilePrimaryButtonStyle"))
    XCTAssertTrue(me.contains("Gateway unavailable"))

    XCTAssertTrue(root.contains(".toolbar(.hidden, for: .tabBar)"))
    XCTAssertTrue(root.contains("AuraTactileTabBar(selection: $selectedTab)"))
    XCTAssertTrue(root.contains(".physicalAuraCard(cornerRadius: 18)"))
    XCTAssertTrue(root.contains("MIRATheme.Color.paperCanvas"))

    XCTAssertFalse(source.contains("LinearGradient"))
    XCTAssertFalse(source.localizedCaseInsensitiveContains("ultraThinMaterial"))
    XCTAssertFalse(source.localizedCaseInsensitiveContains("glass"))
  }
}
