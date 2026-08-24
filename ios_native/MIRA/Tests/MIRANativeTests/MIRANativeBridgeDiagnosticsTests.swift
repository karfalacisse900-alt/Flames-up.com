import XCTest
@testable import MIRANative

final class MIRANativeBridgeDiagnosticsTests: XCTestCase {
  func testRustBridgeStartupProbeExecutesThroughTheLinkedArchive() {
    XCTAssertTrue(MIRANativeBridgeDiagnostics.verifyStartupLinkage())
  }
}
