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
    XCTAssertTrue(theme.contains("light: UIColor(red: 0.969, green: 0.965, blue: 0.953"))
    XCTAssertTrue(theme.contains("public static let paperSurface"))
    XCTAssertTrue(theme.contains("light: UIColor(red: 0.996, green: 0.994, blue: 0.988"))
    XCTAssertTrue(theme.contains("public static let inkBorder"))
    XCTAssertTrue(theme.contains("public static let hardShadow"))

    XCTAssertTrue(community.contains(".stroke(MIRATheme.Color.inkBorder, lineWidth: 1.25)"))
    XCTAssertTrue(community.contains(".shadow(color: MIRATheme.Color.hardShadow, radius: 0, x: 0, y: 3)"))
    XCTAssertTrue(components.contains("AuraTactilePrimaryButtonStyle"))
    XCTAssertTrue(components.contains("AuraTactileSecondaryButtonStyle"))
  }

  func testHomeUsesDenseNeutralRealDataVariantsAndStickyNativeBlur() throws {
    let home = try source("Sources/MIRANative/Screens/Aura/AuraHomeView.swift")
    let community = try source("Sources/MIRANative/Screens/Aura/AuraCommunityViews.swift")
    let source = home + community

    XCTAssertTrue(community.contains("red: 0.969, green: 0.965, blue: 0.953"))
    XCTAssertTrue(home.contains("AuraFeedPalette.canvas.ignoresSafeArea()"))
    XCTAssertTrue(home.contains("LazyVStack(spacing: 9)"))
    XCTAssertTrue(home.contains(".background(.thinMaterial)"))
    XCTAssertTrue(community.contains("AuraSmallPostFeedCard"))
    XCTAssertTrue(community.contains("case micro"))
    XCTAssertTrue(community.contains("case small"))
    XCTAssertTrue(community.contains("case smallWithImage"))
    XCTAssertTrue(community.contains("AuraCommunityPostMedia(post: post, height: 64)"))
    XCTAssertTrue(community.contains("AuraMeetupFeedCard"))
    XCTAssertTrue(community.contains("AuraCommunityPostMedia(post: post, height: 104)"))
    XCTAssertTrue(community.contains(".frame(width: 100)"))
    XCTAssertTrue(community.contains("case compactWithImage"))
    XCTAssertTrue(community.contains("case compactWithoutImage"))
    XCTAssertTrue(community.contains("post.primaryImageURL == nil ? .compactWithoutImage : .compactWithImage"))
    XCTAssertFalse(community.contains("case featured"))
    XCTAssertFalse(community.contains("AuraCommunityPostMedia(post: post, height: 176)"))
    XCTAssertTrue(community.contains("post.primaryImageURL != nil"))
    XCTAssertTrue(community.contains("MIRACachedImage(url: url"))
    XCTAssertTrue(community.contains("HStack(spacing: -8)"))
    XCTAssertTrue(community.contains(".stroke(AuraFeedPalette.ink, lineWidth: 1.25)"))
    XCTAssertTrue(community.contains(".shadow(color: AuraFeedPalette.shadow, radius: 0"))
    XCTAssertTrue(community.contains("AuraCommunityPostMedia(post: post, height: 270, playsVideo: true)"))
    XCTAssertFalse(source.contains("LinearGradient"))
    XCTAssertFalse(source.localizedCaseInsensitiveContains("glass"))
    XCTAssertFalse(home.contains("AuraDocumentTicketCard"))
    XCTAssertFalse(home.contains("walletFeed"))
    XCTAssertFalse(home.contains("proofFeed"))
    XCTAssertFalse(home.contains("networkStrip"))
    XCTAssertFalse(source.localizedCaseInsensitiveContains("Blank Street Coffee"))
  }

  func testScanUsesAutomaticAuraCopyAndTactileActions() throws {
    let scan = try source("Sources/MIRANative/Screens/Aura/AuraScanView.swift")

    XCTAssertTrue(scan.contains("Aura automatically recognizes receipts and invoices."))
    XCTAssertTrue(scan.contains("private var cameraPreviewStage"))
    XCTAssertTrue(scan.contains("private func actualDocumentPreview"))
    XCTAssertTrue(scan.contains("Image(uiImage: image)"))
    XCTAssertTrue(scan.contains("PDFDocument(data: data)?.page(at: 0)"))
    XCTAssertTrue(scan.contains("Label(\"Scan Document\""))
    XCTAssertTrue(scan.contains("Label(\"Photos\""))
    XCTAssertTrue(scan.contains("Label(\"Import\""))
    XCTAssertTrue(scan.contains("AuraTactilePrimaryButtonStyle"))
    XCTAssertTrue(scan.contains("AuraTactileSecondaryButtonStyle"))
    XCTAssertTrue(scan.contains("MIRATheme.Color.paperCanvas.ignoresSafeArea()"))
    XCTAssertTrue(scan.contains(".shadow(color: MIRATheme.Color.hardShadow, radius: 0, x: 0, y: 5)"))
    XCTAssertTrue(scan.contains("merchant: result.merchant.name"))
    XCTAssertTrue(scan.contains("total: result.total"))
    XCTAssertTrue(scan.contains("status: result.documentVerified ? \"Verified\" : \"Could not be verified\""))
    XCTAssertTrue(scan.contains("AuraDocumentScannerView"))
    XCTAssertTrue(scan.contains("PhotosPicker"))
    XCTAssertTrue(scan.contains(".fileImporter("))
    XCTAssertTrue(scan.contains("api.verifyAuraDocument("))
    XCTAssertFalse(scan.contains("private var scanStage"))
    XCTAssertFalse(scan.contains("RECEIPT / INVOICE"))
    XCTAssertFalse(scan.contains("Block #"))
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
    XCTAssertTrue(root.contains(".background(MIRATheme.Color.paperSurface)"))
    XCTAssertTrue(root.contains("MIRATheme.Color.inkBorder.opacity(0.55)"))
    XCTAssertTrue(root.contains("MIRATheme.Color.paperCanvas"))

    XCTAssertFalse(source.contains("LinearGradient"))
    XCTAssertFalse(source.localizedCaseInsensitiveContains("ultraThinMaterial"))
    XCTAssertFalse(source.localizedCaseInsensitiveContains("glass"))
  }
}
